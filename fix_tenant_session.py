import re

PUBLIC_URLS = "axis_saas/public_urls.py"

with open(PUBLIC_URLS, "r") as f:
    content = f.read()

# Define the decorator code (safe, no syntax error)
decorator = '''
def tenant_login_required(view_func):
    """Decorator to ensure user is logged into the specific tenant."""
    def wrapper(request, schema_name, *args, **kwargs):
        tenant = get_school_tenant(schema_name)
        if not tenant:
            return HttpResponseNotFound('School not found')
        # Check authentication AND matching schema
        if not request.session.get('school_admin_authenticated') or \
           request.session.get('school_admin_schema') != tenant.schema_name:
            # Clear stale session data
            request.session.pop('school_admin_authenticated', None)
            request.session.pop('school_admin_schema', None)
            return redirect(f'/portal/{tenant.schema_name}/login/')
        return view_func(request, schema_name, tenant=tenant, *args, **kwargs)
    return wrapper
'''

# Insert decorator after schema_context import
if "def tenant_login_required" not in content:
    # Find a good insertion point
    content = content.replace(
        "from django_tenants.utils import schema_context",
        "from django_tenants.utils import schema_context\n" + decorator
    )
    print("✅ Added tenant_login_required decorator")

# Update school_dashboard
old_dash = """def school_dashboard(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return redirect('/')
    if not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/')
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None})"""

new_dash = """@tenant_login_required
def school_dashboard(request, schema_name, tenant=None):
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None})"""

if old_dash in content:
    content = content.replace(old_dash, new_dash)
    print("✅ Patched school_dashboard")

# Update school_students_list
old_stud = """def school_students_list(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant or not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/' if tenant else '/')
    with schema_context(tenant.schema_name):
        students = Student.objects.all().order_by('-id')
    return render(request, 'tenant/students_list.html', {'tenant': tenant, 'students': students})"""

new_stud = """@tenant_login_required
def school_students_list(request, schema_name, tenant=None):
    with schema_context(tenant.schema_name):
        students = Student.objects.all().order_by('-id')
    return render(request, 'tenant/students_list.html', {'tenant': tenant, 'students': students})"""

if old_stud in content:
    content = content.replace(old_stud, new_stud)
    print("✅ Patched school_students_list")

# Update school_add_student
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

# Update school_settings
old_set = """def school_settings(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant or not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/' if tenant else '/')
    # simplified for brevity – you can restore full version later
    return render(request, 'tenant/settings.html', {'tenant': tenant})"""

new_set = """@tenant_login_required
def school_settings(request, schema_name, tenant=None):
    return render(request, 'tenant/settings.html', {'tenant': tenant})"""

if old_set in content:
    content = content.replace(old_set, new_set)
    print("✅ Patched school_settings")

# Write back
with open(PUBLIC_URLS, "w") as f:
    f.write(content)

print("\n✅ Security patch applied successfully.")
print("👉 Restart your Django server now:")
print("   python manage.py runserver")
