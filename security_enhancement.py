import re
import os

PUBLIC_URLS = "axis_saas/public_urls.py"

with open(PUBLIC_URLS, "r") as f:
    content = f.read()

# 1. Create a decorator function for tenant-specific auth check
decorator_code = """
def tenant_login_required(view_func):
    """Decorator to ensure user is authenticated for the specific tenant schema."""
    def wrapper(request, schema_name, *args, **kwargs):
        tenant = get_school_tenant(schema_name)
        if not tenant:
            return HttpResponseNotFound('School not found')
        # Check both authentication flag and matching schema
        if not request.session.get('school_admin_authenticated') or \
           request.session.get('school_admin_schema') != tenant.schema_name:
            # Clear any stale session data
            request.session.pop('school_admin_authenticated', None)
            request.session.pop('school_admin_schema', None)
            return redirect(f'/portal/{tenant.schema_name}/login/')
        return view_func(request, schema_name, tenant=tenant, *args, **kwargs)
    return wrapper
"""

# Insert decorator after imports (near top, after schema_context import)
if "def tenant_login_required" not in content:
    # Find a good insertion point (after django_tenants.utils import)
    content = content.replace(
        "from django_tenants.utils import schema_context",
        "from django_tenants.utils import schema_context\n" + decorator_code
    )
    print("✅ Added tenant_login_required decorator")

# 2. Modify school_dashboard to use decorator and pass tenant
old_dashboard = """def school_dashboard(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return redirect('/')
    if not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/')
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None})"""

new_dashboard = """@tenant_login_required
def school_dashboard(request, schema_name, tenant=None):
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None})"""

if old_dashboard in content:
    content = content.replace(old_dashboard, new_dashboard)
    print("✅ Patched school_dashboard with tenant check")

# 3. Modify school_students_list
old_students = """def school_students_list(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant or not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/' if tenant else '/')
    with schema_context(tenant.schema_name):
        students = Student.objects.all().order_by('-id')
    return render(request, 'tenant/students_list.html', {'tenant': tenant, 'students': students})"""

new_students = """@tenant_login_required
def school_students_list(request, schema_name, tenant=None):
    with schema_context(tenant.schema_name):
        students = Student.objects.all().order_by('-id')
    return render(request, 'tenant/students_list.html', {'tenant': tenant, 'students': students})"""

if old_students in content:
    content = content.replace(old_students, new_students)
    print("✅ Patched school_students_list")

# 4. Modify school_add_student
old_add = """def school_add_student(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant or not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/' if tenant else '/')
    with schema_context(tenant.schema_name):
        if request.method == 'POST':
            form = StudentAdmissionForm(request.POST)
            if form.is_valid():
                student = form.save(commit=False)
                total = Student.objects.count() + 1
                student.roll_number = f"AX-{tenant.schema_name.upper()}-2026-{total:04d}"
                student.save()
                messages.success(request, f'Student {student.name} added')
                return redirect('school_portal_students', schema_name=tenant.schema_name)
        else:
            form = StudentAdmissionForm()
    return render(request, 'tenant/student_form.html', {'tenant': tenant, 'form': form})"""

new_add = """@tenant_login_required
def school_add_student(request, schema_name, tenant=None):
    with schema_context(tenant.schema_name):
        if request.method == 'POST':
            form = StudentAdmissionForm(request.POST)
            if form.is_valid():
                student = form.save(commit=False)
                total = Student.objects.count() + 1
                student.roll_number = f"AX-{tenant.schema_name.upper()}-2026-{total:04d}"
                student.save()
                messages.success(request, f'Student {student.name} added')
                return redirect('school_portal_students', schema_name=tenant.schema_name)
        else:
            form = StudentAdmissionForm()
    return render(request, 'tenant/student_form.html', {'tenant': tenant, 'form': form})"""

if old_add in content:
    content = content.replace(old_add, new_add)
    print("✅ Patched school_add_student")

# 5. Modify school_settings similarly
old_settings = """def school_settings(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant or not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/' if tenant else '/')
    # simplified for brevity – you can restore full version later
    return render(request, 'tenant/settings.html', {'tenant': tenant})"""

new_settings = """@tenant_login_required
def school_settings(request, schema_name, tenant=None):
    return render(request, 'tenant/settings.html', {'tenant': tenant})"""

if old_settings in content:
    content = content.replace(old_settings, new_settings)
    print("✅ Patched school_settings")

# 6. Also ensure login sets the session with schema, and logout clears it
# (already there, but keep as is)

# Write back
with open(PUBLIC_URLS, "w") as f:
    f.write(content)

# 7. Hardening settings.py: Add security middleware settings
SETTINGS_FILE = "axis_saas/settings.py"
with open(SETTINGS_FILE, "r") as f:
    settings_content = f.read()

# Enable secure cookies if not already (only if DEBUG=False, but we'll add anyway)
if "CSRF_COOKIE_SECURE" not in settings_content:
    settings_content += """
# Security hardening
CSRF_COOKIE_SECURE = False  # Set to True in production with HTTPS
SESSION_COOKIE_SECURE = False  # Set to True in production with HTTPS
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'
SECURE_HSTS_SECONDS = 0  # Enable in production with HTTPS
SECURE_HSTS_INCLUDE_SUBDOMAINS = False
SECURE_HSTS_PRELOAD = False
"""
    with open(SETTINGS_FILE, "a") as f:
        f.write(settings_content)
    print("✅ Added security headers to settings.py")

print("\n✅ Security patch completed. Restart server:")
print("   python manage.py runserver")
