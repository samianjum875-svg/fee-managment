import re

with open('axis_saas/public_urls.py', 'r') as f:
    content = f.read()

# Remove the manual with schema_context blocks (they are no longer needed)
# Replace school_students_list with simpler version
new_students = '''def school_students_list(request, schema_name):
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
    })'''

new_add = '''def school_add_student(request, schema_name):
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
    })'''

# Replace the functions using regex
pattern1 = r'def school_students_list\(request, schema_name\):.*?(?=\ndef school_add_student|\n\nurlpatterns =)'
content = re.sub(pattern1, new_students, content, flags=re.DOTALL)
pattern2 = r'def school_add_student\(request, schema_name\):.*?(?=\n\nurlpatterns =)'
content = re.sub(pattern2, new_add, content, flags=re.DOTALL)

# Remove any lingering schema_context imports if not used
content = content.replace('from django_tenants.utils import schema_context\n', '')

with open('axis_saas/public_urls.py', 'w') as f:
    f.write(content)

print("✅ public_urls.py simplified – middleware now handles schema")
