#!/usr/bin/env python3
import os
import re
import sys

# 1. Add middleware to settings.py if not present
SETTINGS_FILE = "axis_saas/settings.py"
with open(SETTINGS_FILE, "r") as f:
    settings_content = f.read()

middleware_line = "    'axis_saas.middleware.PublicSchemaMiddleware',"
if middleware_line not in settings_content:
    # Insert after 'django_tenants.middleware.main.TenantMainMiddleware'
    settings_content = settings_content.replace(
        "    'django_tenants.middleware.main.TenantMainMiddleware',",
        "    'django_tenants.middleware.main.TenantMainMiddleware',\n" + middleware_line,
    )
    with open(SETTINGS_FILE, "w") as f:
        f.write(settings_content)
    print("✅ Added PublicSchemaMiddleware to settings.py")
else:
    print("ℹ️ PublicSchemaMiddleware already in settings.py")

# 2. Patch public_urls.py to use schema_context explicitly (fallback if middleware fails)
PUBLIC_URLS = "axis_saas/public_urls.py"
with open(PUBLIC_URLS, "r") as f:
    urls_content = f.read()

# Ensure import
if "from django_tenants.utils import schema_context" not in urls_content:
    urls_content = urls_content.replace(
        "from django.contrib import messages",
        "from django.contrib import messages\nfrom django_tenants.utils import schema_context"
    )

# Fix school_students_list
old_students = """def school_students_list(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School portal not found.')

    if request.session.get('school_admin_authenticated') is not True or request.session.get('school_admin_schema') != tenant.schema_name:
        return redirect(f'/portal/{tenant.schema_name}/login/')

    logo_url = tenant.school_logo.url if tenant.school_logo else None
    
    # Middleware already set the schema, so direct query works
    from axis_saas.models import Student
    students = Student.objects.all().order_by('-id')

    return render(request, 'tenant/students_list.html', {
        'tenant': tenant,
        'logo_url': logo_url,
        'students': students,
    })"""

new_students = """def school_students_list(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School portal not found.')

    if request.session.get('school_admin_authenticated') is not True or request.session.get('school_admin_schema') != tenant.schema_name:
        return redirect(f'/portal/{tenant.schema_name}/login/')

    logo_url = tenant.school_logo.url if tenant.school_logo else None
    
    from axis_saas.models import Student
    from django_tenants.utils import schema_context
    with schema_context(tenant.schema_name):
        students = Student.objects.all().order_by('-id')

    return render(request, 'tenant/students_list.html', {
        'tenant': tenant,
        'logo_url': logo_url,
        'students': students,
    })"""

if old_students in urls_content:
    urls_content = urls_content.replace(old_students, new_students)
    print("✅ Patched school_students_list with schema_context")

# Fix school_add_student
old_add = """def school_add_student(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School portal not found.')

    if request.session.get('school_admin_authenticated') is not True or request.session.get('school_admin_schema') != tenant.schema_name:
        return redirect(f'/portal/{tenant.schema_name}/login/')

    # Middleware handles schema, so no with schema_context needed
    if request.method == 'POST':
        form = StudentAdmissionForm(request.POST)
        if form.is_valid():
            student = form.save(commit=False)
            total_students = Student.objects.count() + 1
            student.roll_number = f"AX-{tenant.schema_name.upper()}-{2026}-{total_students:04d}"
            student.save()
            messages.success(request, f"Student {student.name} added successfully. Roll: {student.roll_number}")
            return redirect('school_portal_students', schema_name=tenant.schema_name)
    else:
        form = StudentAdmissionForm()

    logo_url = tenant.school_logo.url if tenant.school_logo else None
    return render(request, 'tenant/student_form.html', {
        'tenant': tenant,
        'form': form,
        'logo_url': logo_url,
    })"""

new_add = """def school_add_student(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School portal not found.')

    if request.session.get('school_admin_authenticated') is not True or request.session.get('school_admin_schema') != tenant.schema_name:
        return redirect(f'/portal/{tenant.schema_name}/login/')

    from django_tenants.utils import schema_context
    with schema_context(tenant.schema_name):
        if request.method == 'POST':
            form = StudentAdmissionForm(request.POST)
            if form.is_valid():
                student = form.save(commit=False)
                total_students = Student.objects.count() + 1
                student.roll_number = f"AX-{tenant.schema_name.upper()}-{2026}-{total_students:04d}"
                student.save()
                messages.success(request, f"Student {student.name} added successfully. Roll: {student.roll_number}")
                return redirect('school_portal_students', schema_name=tenant.schema_name)
        else:
            form = StudentAdmissionForm()

    logo_url = tenant.school_logo.url if tenant.school_logo else None
    return render(request, 'tenant/student_form.html', {
        'tenant': tenant,
        'form': form,
        'logo_url': logo_url,
    })"""

if old_add in urls_content:
    urls_content = urls_content.replace(old_add, new_add)
    print("✅ Patched school_add_student with schema_context")

with open(PUBLIC_URLS, "w") as f:
    f.write(urls_content)

# 3. Clean public schema's student table (delete the leaked 4 rows)
print("\n🧹 Cleaning leaked student data from public schema...")
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
import django
django.setup()
from django.db import connection
try:
    with connection.cursor() as cur:
        cur.execute("DELETE FROM axis_saas_student WHERE true")
        print(f"✅ Deleted {cur.rowcount} rows from public.axis_saas_student")
except Exception as e:
    print(f"⚠️ Could not delete public student rows: {e}")

print("\n" + "="*50)
print("✅ FIX COMPLETE. Now RESTART server:")
print("   python manage.py runserver")
print("="*50)
