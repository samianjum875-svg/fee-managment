import os

def apply_patch():
    # Paths based on your provided directory structure
    view_file = 'axis_saas/tenant_views.py'
    template_file = 'templates/tenant/students_list.html'

    # 1. Update the View logic
    with open(view_file, 'r') as f:
        content = f.read()

    # The view needs to point to the correct template path
    new_view_code = """
@login_required
def student_management_view(request):
    if request.tenant.schema_name == 'public':
        return redirect('/admin/')

    if request.method == 'POST':
        form = StudentAdmissionForm(request.POST)
        if form.is_valid():
            student = form.save(commit=False)
            total_students = Student.objects.count() + 1
            student.roll_number = f"AX-{request.tenant.schema_name.upper()}-{2026}-{total_students:04d}"
            student.save()
            messages.success(request, f"Student {student.name} provisioned successfully.")
            return redirect('school_portal_students')
    else:
        form = StudentAdmissionForm()
    
    students = Student.objects.all().order_by('-enrolled_on')
    return render(request, 'tenant/students_list.html', {'students': students, 'form': form})
"""
    # Replace the existing function
    if "def student_management_view(request):" in content:
        # regex-like replacement of the function block
        start_idx = content.find("def student_management_view(request):")
        end_idx = content.find("return render(request, 'templates/students_list.html'", start_idx) + 100
        # If the find failed, just append (safety)
        if start_idx != -1:
            content = content[:start_idx] + new_view_code + content[content.find("return render", end_idx):]

    with open(view_file, 'w') as f:
        f.write(content)

    # 2. Update the Template (Inject Form)
    with open(template_file, 'r') as f:
        tmpl = f.read()

    form_html = """
<div class="form-card" style="margin-bottom: 20px;">
    <h3>Enroll New Student</h3>
    <form method="POST">
        {% csrf_token %}
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
            {% for field in form %}
            <div class="field-card">
                <label>{{ field.label }}</label>
                {{ field }}
            </div>
            {% endfor %}
        </div>
        <button type="submit" style="margin-top: 16px; padding: 10px 20px; background: var(--primary); color: white; border-radius: 6px; cursor: pointer;">Submit Enrollment</button>
    </form>
</div>
"""
    # Inject before the table
    if "Enroll New Student" not in tmpl:
        tmpl = tmpl.replace('{% block body %}', '{% block body %}' + form_html)
    
    with open(template_file, 'w') as f:
        f.write(tmpl)

    print("UI patch applied successfully.")
    os.remove('fix_and_patch_ui.py')

if __name__ == "__main__":
    apply_patch()
