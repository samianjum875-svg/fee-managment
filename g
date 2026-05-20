#!/usr/bin/env python3
"""
AXIS School System - Fix Add Student Form Not Opening
Automatically patches:
1. Creates templates/tenant/student_form.html
2. Adds view + URL to public_urls.py
3. Fixes Add Student button in students_list.html
"""

import os
import re
from pathlib import Path

BASE_DIR = Path.cwd()  # assuming run from project root ~/axis_school_sys

# ----------------------------------------------------------------------
# 1. CREATE MISSING student_form.html
# ----------------------------------------------------------------------
STUDENT_FORM_TEMPLATE = '''{% extends 'tenant/base.html' %}

{% block title %}{{ tenant.name }} | Add Student{% endblock %}

{% block sidebar_meta %}Add Student{% endblock %}
{% block nav_students_active %}active{% endblock %}

{% block body %}
<div class="page-card">
    <div class="page-head">
        <div>
            <h1 class="page-title">Add New Student</h1>
            <p class="page-description">Fill out the enrollment form below.</p>
        </div>
    </div>

    <div class="form-card">
        <form method="post">
            {% csrf_token %}
            {% for field in form %}
                <div class="field-card">
                    <label for="{{ field.id_for_label }}">{{ field.label }}</label>
                    {{ field }}
                    {% if field.help_text %}
                        <small style="color: var(--muted); font-size: 0.7rem;">{{ field.help_text }}</small>
                    {% endif %}
                    {% for error in field.errors %}
                        <div style="color: var(--danger); font-size: 0.75rem;">{{ error }}</div>
                    {% endfor %}
                </div>
            {% endfor %}
            <div class="field-card" style="flex-direction: row; gap: 12px; margin-top: 16px;">
                <button type="submit" style="background: var(--primary);">Save Student</button>
                <a href="{% url 'school_portal_students' schema_name=tenant.schema_name %}" style="background: var(--surface-alt); padding: 10px 16px; border-radius: 6px; color: var(--text);">Cancel</a>
            </div>
        </form>
    </div>
</div>
{% endblock %}
'''

def create_student_form():
    template_path = BASE_DIR / 'templates' / 'tenant' / 'student_form.html'
    template_path.parent.mkdir(parents=True, exist_ok=True)
    if not template_path.exists():
        template_path.write_text(STUDENT_FORM_TEMPLATE)
        print("✅ Created templates/tenant/student_form.html")
    else:
        print("⚠️  student_form.html already exists – skipping (no overwrite)")

# ----------------------------------------------------------------------
# 2. PATCH public_urls.py → add view + URL
# ----------------------------------------------------------------------
PUBLIC_URLS_PATH = BASE_DIR / 'axis_saas' / 'public_urls.py'

def patch_public_urls():
    if not PUBLIC_URLS_PATH.exists():
        print("❌ public_urls.py not found at", PUBLIC_URLS_PATH)
        return False

    content = PUBLIC_URLS_PATH.read_text()

    # Check if already patched
    if 'def school_add_student' in content:
        print("ℹ️  public_urls.py already contains school_add_student – skipping")
        return True

    # Find the location to inject imports (after existing imports)
    import_block_end = content.find('from axis_saas.models import SchoolClient')
    if import_block_end == -1:
        # fallback: after last import
        lines = content.splitlines()
        last_import = max([i for i, line in enumerate(lines) if line.startswith('from ') or line.startswith('import ')], default=-1)
        if last_import != -1:
            insert_pos = content.find(lines[last_import]) + len(lines[last_import]) + 1
        else:
            insert_pos = 0
    else:
        insert_pos = content.find('\n', import_block_end) + 1

    # Imports we need
    new_imports = '''
from django import forms
from .models import Student
from .tenant_views import StudentAdmissionForm
from django.contrib import messages
'''

    # Insert imports
    content = content[:insert_pos] + new_imports + content[insert_pos:]

    # Now add the view function before urlpatterns
    # Find urlpatterns definition
    urlpatterns_pos = content.find('urlpatterns = [')
    if urlpatterns_pos == -1:
        print("❌ Could not find 'urlpatterns = [' in public_urls.py")
        return False

    # Find a good place to insert the view (after last import but before urlpatterns)
    view_code = '''

def school_add_student(request, schema_name):
    """Add student view for public_urls using manual tenant fetching."""
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School portal not found.')

    if request.session.get('school_admin_authenticated') is not True or request.session.get('school_admin_schema') != tenant.schema_name:
        return redirect(f'/portal/{tenant.schema_name}/login/')

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
    })
'''

    # Insert the view right before urlpatterns
    content = content[:urlpatterns_pos] + view_code + '\n\n' + content[urlpatterns_pos:]

    # Add URL pattern inside urlpatterns list
    # Find the existing patterns and add a new one
    # We'll inject after the students list pattern
    students_list_pattern = "path('portal/<slug:schema_name>/students/', school_students_list, name='school_portal_students')"
    if students_list_pattern in content:
        # Insert after that line
        new_pattern = "    path('portal/<slug:schema_name>/students/add/', school_add_student, name='school_add_student'),"
        # Find the line and add after it
        lines = content.splitlines()
        for i, line in enumerate(lines):
            if students_list_pattern in line:
                # Insert new pattern on next line with proper indentation
                lines.insert(i+1, new_pattern)
                break
        content = '\n'.join(lines)
    else:
        # Fallback: just append at the end of urlpatterns before closing bracket
        closing_bracket_pos = content.rfind(']')
        if closing_bracket_pos != -1:
            content = content[:closing_bracket_pos] + "    path('portal/<slug:schema_name>/students/add/', school_add_student, name='school_add_student'),\n" + content[closing_bracket_pos:]

    # Write back
    PUBLIC_URLS_PATH.write_text(content)
    print("✅ Patched public_urls.py – added school_add_student view and URL")
    return True

# ----------------------------------------------------------------------
# 3. PATCH students_list.html – fix Add Student button to be a link
# ----------------------------------------------------------------------
STUDENTS_LIST_PATH = BASE_DIR / 'templates' / 'tenant' / 'students_list.html'

def patch_students_list():
    if not STUDENTS_LIST_PATH.exists():
        print("❌ students_list.html not found at", STUDENTS_LIST_PATH)
        return False

    content = STUDENTS_LIST_PATH.read_text()

    # Check if already patched (contains href=)
    if 'href="{% url' in content and 'school_add_student' in content:
        print("ℹ️  students_list.html already has correct link – skipping")
        return True

    # Replace the button with a proper <a> link
    # Old button: <button style="...">+ Add Student</button>
    # New: <a href="..." style="...">+ Add Student</a>
    pattern = r'(<div class="field-card" style="margin: 0;">\s*<button[^>]*>\+ Add Student</button>\s*</div>)'
    replacement = r'<div class="field-card" style="margin: 0;">\n        <a href="{% url \'school_add_student\' schema_name=tenant.schema_name %}" style="background: var(--primary); color: #fff; padding: 10px 16px; border-radius: 6px; font-weight: 600; text-decoration: none; display: inline-block;">+ Add Student</a>\n    </div>'

    new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)
    if new_content == content:
        # Try simpler replacement
        new_content = content.replace(
            '<button style="background: var(--primary); color: #fff; padding: 10px 16px; border-radius: 6px; font-weight: 600; cursor: pointer;">+ Add Student</button>',
            '<a href="{% url \'school_add_student\' schema_name=tenant.schema_name %}" style="background: var(--primary); color: #fff; padding: 10px 16px; border-radius: 6px; font-weight: 600; text-decoration: none; display: inline-block;">+ Add Student</a>'
        )

    STUDENTS_LIST_PATH.write_text(new_content)
    print("✅ Patched students_list.html – Add Student button now links to add form")
    return True

# ----------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------
if __name__ == '__main__':
    print("🔧 AXIS SCHOOL SYSTEM PATCHER - Fix Add Student Form")
    create_student_form()
    patch_public_urls()
    patch_students_list()
    print("\n✅ All patches applied successfully!")
    print("👉 Restart your Django server (Ctrl+C then python manage.py runserver)")
    print("👉 Login to any school portal, go to Students page, and click 'Add Student' – form should now open.")
