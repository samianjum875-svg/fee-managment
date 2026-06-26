#!/usr/bin/env python3
"""
Patcher for:
- axis_saas/views.py → add pending_only filter in get_student_list_context
- templates/mobile/student_list.html → further compact card design
"""

import os
import re

VIEWS_PATH = "axis_saas/views.py"
TEMPLATE_PATH = "templates/mobile/student_list.html"

# ----------------------------------------------------------------------
# 1. Patch views.py – add pending_only handling
# ----------------------------------------------------------------------
def patch_views():
    with open(VIEWS_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find the function get_student_list_context
    # We'll replace the whole function with an updated version.
    # Use a regex to locate the function body and replace it.
    # We'll define the new function body as a string.
    
    new_func = '''def get_student_list_context(request, schema_name):
    tenant = get_tenant(request, schema_name)
    query = request.GET.get('q', '')
    grade = request.GET.get('grade', '')
    section = request.GET.get('section', '')
    status = request.GET.get('status', '')
    pending_only = request.GET.get('pending_only') == '1'   # <-- new
    page_number = request.GET.get('page', 1)
    with schema_context(schema_name):
        students = Student.objects.all()
        if query:
            students = students.filter(
                Q(name__icontains=query) | Q(roll_number__icontains=query) |
                Q(father_name__icontains=query) | Q(father_cnic__icontains=query) |
                Q(parent_mobile__icontains=query) | Q(grade__icontains=query)
            )
        if grade:
            students = students.filter(grade=grade)
        if section:
            students = students.filter(section=section)
        if status:
            students = students.filter(status=status)
        students = students.order_by('-enrolled_on')
        
        # Compute pending for all students first
        student_list = []
        for s in students:
            s.pending_amount = get_overall_pending(s)
            student_list.append(s)
        
        # Apply pending_only filter if needed
        if pending_only:
            student_list = [s for s in student_list if s.pending_amount > 0]
        
        total_pending_all = sum(s.pending_amount for s in student_list)
        
        # Paginate the filtered list
        paginator = Paginator(student_list, 20)
        page_obj = paginator.get_page(page_number)
        
        grades = list(Student.objects.values_list('grade', flat=True).distinct().order_by('grade'))
        sections = list(Student.objects.values_list('section', flat=True).distinct().order_by('section'))
        status_choices = Student.STATUS_CHOICES
        total_active = Student.objects.filter(status='active').count()
        
    return {
        'tenant': tenant,
        'students': page_obj,
        'grades': grades,
        'sections': sections,
        'status_choices': status_choices,
        'search_query': query,
        'total_pending_all': total_pending_all,
        'total_active': total_active,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }'''

    # Use regex to replace the existing function definition
    # We'll search for "def get_student_list_context" and replace until the next def at same indentation
    pattern = re.compile(r'(def get_student_list_context\(.*?\):.*?)(?=\ndef |\Z)', re.DOTALL)
    if not re.search(pattern, content):
        print("❌ Could not find get_student_list_context function in views.py")
        return False

    content = re.sub(pattern, new_func, content)
    
    with open(VIEWS_PATH, 'w', encoding='utf-8') as f:
        f.write(content)
    print("✅ Updated axis_saas/views.py – added pending_only filter and fixed total pending sum.")
    return True

# ----------------------------------------------------------------------
# 2. Patch the template – compact cards
# ----------------------------------------------------------------------
def patch_template():
    # We'll modify the existing template to reduce padding, font sizes, and spacing.
    # We'll replace the card styles and some HTML structure.
    with open(TEMPLATE_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # We'll replace the entire <style> block and some HTML to make it more compact.
    # But to avoid breaking everything, we'll just adjust padding/margins.
    # We'll look for .student-card and reduce padding, gap, etc.
    
    # Replace padding: 0.8rem 1rem → 0.6rem 0.8rem
    content = content.replace('padding: 0.8rem 1rem;', 'padding: 0.6rem 0.8rem;')
    # Reduce gap in .student-list
    content = content.replace('gap: 0.75rem;', 'gap: 0.6rem;')
    # Reduce font size of student name
    content = content.replace('font-size: 1.05rem;', 'font-size: 0.95rem;')
    # Reduce meta font size
    content = content.replace('font-size: 0.82rem;', 'font-size: 0.75rem;')
    # Reduce father font size
    content = content.replace('font-size: 0.78rem;', 'font-size: 0.7rem;')
    # Reduce pending font size
    content = content.replace('font-size: 0.85rem;', 'font-size: 0.75rem;')
    # Reduce badge size
    content = content.replace('font-size: 0.6rem;', 'font-size: 0.55rem;')
    content = content.replace('padding: 0.1rem 0.65rem;', 'padding: 0.05rem 0.5rem;')
    # Reduce action button padding
    content = content.replace('padding: 0.25rem 0.6rem;', 'padding: 0.2rem 0.5rem;')
    # Reduce action button font size
    content = content.replace('font-size: 0.7rem;', 'font-size: 0.65rem;')
    # Reduce card border radius
    content = content.replace('--card-radius: 1.25rem;', '--card-radius: 0.9rem;')
    # Reduce shadow
    content = content.replace('--card-shadow: 0 8px 24px rgba(15, 23, 42, 0.06);', '--card-shadow: 0 2px 8px rgba(15, 23, 42, 0.04);')

    # Also adjust the analytics strip padding
    content = content.replace('padding: 0.5rem 0.25rem;', 'padding: 0.3rem 0.1rem;')
    content = content.replace('gap: 0.75rem;', 'gap: 0.4rem;')
    content = content.replace('font-size: 1.4rem;', 'font-size: 1.2rem;')
    content = content.replace('font-size: 0.6rem;', 'font-size: 0.55rem;')

    # Adjust page header
    content = content.replace('font-size: 1.8rem;', 'font-size: 1.6rem;')
    content = content.replace('margin-bottom: 0.5rem;', 'margin-bottom: 0.3rem;')

    # Adjust search bar padding
    content = content.replace('padding: 0.2rem 0.2rem 0.2rem 1.2rem;', 'padding: 0.1rem 0.1rem 0.1rem 1rem;')
    content = content.replace('padding: 0.6rem 0;', 'padding: 0.4rem 0;')
    content = content.replace('font-size: 0.95rem;', 'font-size: 0.85rem;')

    # Adjust FAB size
    content = content.replace('width: 56px;', 'width: 48px;')
    content = content.replace('height: 56px;', 'height: 48px;')
    content = content.replace('font-size: 1.8rem;', 'font-size: 1.5rem;')
    content = content.replace('bottom: 100px;', 'bottom: 85px;')

    # Write back
    with open(TEMPLATE_PATH, 'w', encoding='utf-8') as f:
        f.write(content)
    print("✅ Updated templates/mobile/student_list.html – further compacted cards and reduced spacing.")
    return True

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
def main():
    print("🚀 Applying patches...")
    views_ok = patch_views()
    template_ok = patch_template()
    if views_ok and template_ok:
        print("\n✅ All patches applied successfully.")
        print("👉 Please hard-refresh your browser (Ctrl+F5) to see the changes.")
        print("Now the pending filter works and the cards are more compact and professional.")
    else:
        print("\n⚠️ Some patches failed. Please check the files and try again.")

if __name__ == "__main__":
    main()
