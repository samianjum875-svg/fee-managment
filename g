#!/usr/bin/env python3
"""
AXIS Fee Collection – Move inline payment form to separate page.
Run this script ONCE on your local machine.
It will:
  - Modify views.py to render different template when student_id is given.
  - Remove the inline selected-student section from fee_collection.html.
  - Keep all existing URL patterns and functionality intact.
"""

import re
import os
import shutil
from pathlib import Path

BASE_DIR = Path(__file__).parent
VIEWS_FILE = BASE_DIR / "axis_saas" / "views.py"
TEMPLATE_FILE = BASE_DIR / "templates" / "tenant" / "fee_collection.html"
COLLECT_TEMPLATE = BASE_DIR / "templates" / "tenant" / "collect_fee.html"

def backup_file(filepath):
    backup = filepath.with_suffix(filepath.suffix + ".bak")
    if not backup.exists():
        shutil.copy2(filepath, backup)
        print(f"📁 Backup created: {backup}")
    else:
        print(f"ℹ️ Backup already exists: {backup}")

def patch_views():
    """Modify fee_collection view to use separate template when student_id given."""
    if not VIEWS_FILE.exists():
        print(f"❌ {VIEWS_FILE} not found!")
        return False

    backup_file(VIEWS_FILE)
    content = VIEWS_FILE.read_text()

    # Find the existing fee_collection function
    # We'll replace the whole function with a new version that uses different templates.
    # The current function starts with: def fee_collection(request, schema_name, student_id=None):
    # We'll keep the same signature but change internal logic.

    # Look for the function definition
    pattern = r'(def fee_collection\(request, schema_name, student_id=None\):.*?)(?=\n@csrf_exempt|\n\ndef [a-zA-Z]|\Z)'
    match = re.search(pattern, content, re.DOTALL)
    if not match:
        print("❌ Could not find fee_collection function in views.py")
        return False

    old_func = match.group(1)

    # New function: if student_id is provided, render collect_fee.html, else render fee_collection.html without inline section.
    # We'll also keep the POST handling exactly the same for both cases.
    # But note: the current POST logic expects student_id to be passed in POST data; it uses redirect('fee_collection', ... student_id=student.id) after payment.
    # That's fine; it will go to the student-specific URL.

    new_func = '''def fee_collection(request, schema_name, student_id=None):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        # Handle POST payment (works for both list and student views)
        if request.method == 'POST':
            student_id_post = request.POST.get('student_id')
            amount = request.POST.get('amount')
            payment_mode = request.POST.get('payment_mode')
            remarks = request.POST.get('remarks', '')
            if student_id_post and amount:
                try:
                    student = Student.objects.get(id=student_id_post)
                    amount = Decimal(amount)
                    pending_records = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date')
                    total_pending = sum(r.remaining for r in pending_records)
                    if amount > total_pending:
                        messages.error(request, f"Amount exceeds total pending (₹{total_pending})")
                        return redirect('fee_collection', schema_name=schema_name, student_id=student.id)
                    remaining = amount
                    paid_records = []
                    for record in pending_records:
                        if remaining <= 0:
                            break
                        due = record.remaining
                        if remaining >= due:
                            record.paid_amount = record.amount
                            remaining -= due
                        else:
                            record.paid_amount += remaining
                            remaining = 0
                        record.save()
                        paid_records.append(record)
                    payment = PaymentTransaction.objects.create(
                        student=student,
                        amount=amount,
                        payment_mode=payment_mode,
                        payment_type='full' if remaining == 0 else 'partial',
                        remarks=remarks,
                        created_by=request.session.get('school_admin_username', 'admin')
                    )
                    payment.fee_records.set(paid_records)
                    messages.success(request, f"Payment of ₹{amount} received. Receipt: {payment.receipt_number}")
                    return redirect('fee_receipt', schema_name=schema_name, receipt_id=payment.id)
                except Student.DoesNotExist:
                    messages.error(request, "Student not found")
                except Exception as e:
                    messages.error(request, f"Error processing payment: {str(e)}")
            else:
                messages.error(request, "Invalid payment data")
            return redirect('fee_collection', schema_name=schema_name)

        # ---------- GET request ----------
        # If student_id is provided, show the dedicated payment page for that student
        if student_id is not None:
            try:
                student = Student.objects.get(id=student_id)
                pending_records = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date')
                total_pending = sum(r.remaining for r in pending_records)
                context = {
                    'tenant': tenant,
                    'student': student,
                    'pending_records': pending_records,
                    'total_pending': total_pending,
                    'logo_url': tenant.school_logo.url if tenant.school_logo else None,
                }
                return render(request, 'tenant/collect_fee.html', context)
            except Student.DoesNotExist:
                messages.error(request, "Student not found")
                return redirect('fee_collection', schema_name=schema_name)

        # Otherwise, show the list of students with pending fees (no inline section)
        search_filter = request.GET.get('pending_search', '')
        grade_filter = request.GET.get('pending_grade', '')
        section_filter = request.GET.get('pending_section', '')
        page_number = request.GET.get('page', 1)

        students_qs = Student.objects.all()
        if search_filter:
            students_qs = students_qs.filter(
                Q(name__icontains=search_filter) | Q(roll_number__icontains=search_filter) |
                Q(father_name__icontains=search_filter) | Q(father_cnic__icontains=search_filter)
            )
        if grade_filter:
            students_qs = students_qs.filter(grade=grade_filter)
        if section_filter:
            students_qs = students_qs.filter(section=section_filter)

        pending_students = []
        for s in students_qs:
            pending = sum(fr.remaining for fr in s.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            if pending > 0:
                s.pending_total = pending
                pending_students.append(s)
        pending_students.sort(key=lambda x: x.pending_total, reverse=True)

        paginator = Paginator(pending_students, 20)
        pending_page = paginator.get_page(page_number)

        total_pending_all = sum(fr.remaining for fr in FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue']))
        total_payments_count = PaymentTransaction.objects.count()
        recent_payments = list(PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:5])
        grades = list(Student.objects.values_list('grade', flat=True).distinct().order_by('grade'))
        sections = list(Student.objects.values_list('section', flat=True).distinct().order_by('section'))

        context = {
            'tenant': tenant,
            'pending_students': pending_page,
            'recent_payments': recent_payments,
            'total_pending_all': total_pending_all,
            'total_payments_count': total_payments_count,
            'grades': grades,
            'sections': sections,
            'search_filter': search_filter,
            'grade_filter': grade_filter,
            'section_filter': section_filter,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
        return render(request, 'tenant/fee_collection.html', context)'''

    # Replace the old function with new one
    new_content = content.replace(old_func, new_func)
    VIEWS_FILE.write_text(new_content)
    print("✅ views.py patched: fee_collection now uses separate template for student view")
    return True

def patch_template():
    """Remove the inline selected-student section from fee_collection.html."""
    if not TEMPLATE_FILE.exists():
        print(f"⚠️ {TEMPLATE_FILE} not found, skipping template patch")
        return

    backup_file(TEMPLATE_FILE)
    content = TEMPLATE_FILE.read_text()

    # Find the selected student block and remove it entirely
    # Look for {% if selected_student %} ... {% endif %} and remove.
    # Also remove the empty student panel placeholder if any.
    # We'll use a regex that matches from the comment or start of the block to the end of the endif.
    # The block in the file starts with "<!-- Selected Student & Payment Form -->" or directly "{% if selected_student %}".
    # We'll remove everything between that line and the line containing "{% endif %}" that closes it.
    pattern = r'(<!-- Selected Student & Payment Form -->.*?{% endif %}\s*</div>\s*{% endif %})|({% if selected_student %}.*?{% endif %}\s*</div>\s*{% endif %})'
    content = re.sub(pattern, '', content, flags=re.DOTALL)

    # Also remove any empty lines left
    content = re.sub(r'\n\s*\n', '\n', content)

    TEMPLATE_FILE.write_text(content)
    print("✅ Removed inline payment section from fee_collection.html")
    print("   (the 'Select' buttons will now redirect to separate page)")

def ensure_collect_template():
    """Make sure collect_fee.html exists and is correctly styled (it already does)."""
    if not COLLECT_TEMPLATE.exists():
        print(f"⚠️ {COLLECT_TEMPLATE} not found! The new view expects it.")
        print("   Please ensure the template exists. If missing, restore from backup.")
    else:
        print("✅ collect_fee.html found – will be used for single student payment")

def main():
    print("🚀 AXIS Fee Collection – Separate Page Patcher\n")
    if patch_views():
        patch_template()
        ensure_collect_template()
        print("\n✨ Done! Restart your server:")
        print("   source venv/bin/activate")
        print("   python manage.py runserver")
        print("\n👉 Now clicking 'Select' on any student will open a dedicated payment page.")
        print("   The main Fee Collection page shows only the student list.")
    else:
        print("❌ Patcher failed. No changes were made.")

if __name__ == "__main__":
    main()
