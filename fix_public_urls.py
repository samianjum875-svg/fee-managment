#!/usr/bin/env python3
import re

PUBLIC_URLS = "axis_saas/public_urls.py"

with open(PUBLIC_URLS, "r") as f:
    content = f.read()

# Replace the broken school_students_list function with correct version
new_students_list = '''def school_students_list(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School portal not found.')

    if request.session.get('school_admin_authenticated') is not True or request.session.get('school_admin_schema') != tenant.schema_name:
        return redirect(f'/portal/{tenant.schema_name}/login/')

    logo_url = tenant.school_logo.url if tenant.school_logo else None
    
    # Switch to tenant schema for data isolation
    from axis_saas.models import Student
    from django_tenants.utils import schema_context
    with schema_context(tenant.schema_name):
        students = Student.objects.all().order_by('-id')

    return render(request, 'tenant/students_list.html', {
        'tenant': tenant,
        'logo_url': logo_url,
        'students': students,
    })'''

# Replace the broken school_add_student function
new_add_student = '''def school_add_student(request, schema_name):
    """Add student view for public_urls using manual tenant fetching."""
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
    })'''

# Find and replace the functions using regex (non-greedy)
# First, remove the old school_students_list
pattern_students = r'def school_students_list\(request, schema_name\):.*?(?=\n\ndef school_add_student|\n\nurlpatterns =)'
content = re.sub(pattern_students, new_students_list, content, flags=re.DOTALL)

# Then replace school_add_student
pattern_add = r'def school_add_student\(request, schema_name\):.*?(?=\n\nurlpatterns =)'
content = re.sub(pattern_add, new_add_student, content, flags=re.DOTALL)

# Also ensure the import is present (it is already)
if "from django_tenants.utils import schema_context" not in content:
    # Insert after the other imports
    content = content.replace(
        "from django.contrib import messages",
        "from django.contrib import messages\nfrom django_tenants.utils import schema_context"
    )

# Write back
with open(PUBLIC_URLS, "w") as f:
    f.write(content)

print("✅ Fixed public_urls.py syntax and tenant isolation")
print("👉 Restart Django server: python manage.py runserver")
