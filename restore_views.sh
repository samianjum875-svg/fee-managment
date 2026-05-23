#!/bin/bash

# restore_views.sh - Adds missing view functions to axis_saas/views.py
# Run from: ~/axis_school_sys

set -e

VIEWS_FILE="axis_saas/views.py"

if [ ! -f "$VIEWS_FILE" ]; then
    echo "ERROR: $VIEWS_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup original
if [ ! -f "${VIEWS_FILE}.bak2" ]; then
    cp "$VIEWS_FILE" "${VIEWS_FILE}.bak2"
    echo "✅ Backup saved as ${VIEWS_FILE}.bak2"
fi

# Check if functions already exist
if grep -q "^def settings(" "$VIEWS_FILE"; then
    echo "All functions appear to be present. Nothing to do."
    exit 0
fi

echo "✍️  Appending missing view functions to $VIEWS_FILE ..."

cat >> "$VIEWS_FILE" << 'EOF'

# ------------------- Settings -------------------
def settings(request, schema_name):
    tenant = get_tenant(request, schema_name)
    if request.method == 'POST':
        school_name = request.POST.get('school_name', '').strip()
        if school_name:
            tenant.name = school_name
        admin_username = request.POST.get('admin_username', '').strip()
        admin_password = request.POST.get('admin_password', '')
        admin_password_confirm = request.POST.get('admin_password_confirm', '')
        if admin_username:
            tenant.admin_username = admin_username
        if admin_password:
            if admin_password == admin_password_confirm:
                tenant.admin_password = admin_password
            else:
                messages.error(request, "Passwords do not match.")
                return redirect('settings', schema_name=schema_name)
        if request.FILES.get('school_logo'):
            tenant.school_logo = request.FILES['school_logo']
        tenant.save()
        messages.success(request, "Settings updated successfully.")
        return redirect('settings', schema_name=schema_name)
    context = {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/settings.html', context)

# ------------------- Fee Structure -------------------
def fee_structure(request, schema_name):
    tenant = get_tenant(request, schema_name)
    edit_grade = request.GET.get('edit', '')
    with schema_context(schema_name):
        if request.method == 'POST':
            grade = request.POST.get('grade')
            monthly_fee = request.POST.get('monthly_fee')
            obj, created = FeeStructure.objects.update_or_create(grade=grade, defaults={'monthly_fee': monthly_fee})
            Student.objects.filter(grade=grade).update(custom_fee=monthly_fee)
            messages.success(request, f"Fee structure for {grade} saved.")
            return redirect('fee_structure', schema_name=schema_name)
        structures = FeeStructure.objects.all().order_by('grade')
        form = FeeStructureForm()
        if edit_grade:
            try:
                edit_obj = FeeStructure.objects.get(grade=edit_grade)
                form = FeeStructureForm(initial={'grade': edit_obj.grade, 'monthly_fee': edit_obj.monthly_fee})
            except FeeStructure.DoesNotExist:
                pass
    context = {
        'tenant': tenant, 'form': form, 'fee_structures': structures, 'edit_grade': edit_grade,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/fee_structure.html', context)

# ------------------- Fee Settings -------------------
def fee_settings(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        settings_obj, created = SchoolFeeSettings.objects.get_or_create(pk=1)
        if request.method == 'POST':
            form = FeeSettingsForm(request.POST, instance=settings_obj)
            if form.is_valid():
                form.save()
                messages.success(request, "Fee settings updated.")
                return redirect('fee_settings', schema_name=schema_name)
        else:
            form = FeeSettingsForm(instance=settings_obj)
    context = {'tenant': tenant, 'form': form, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/fee_settings.html', context)

# ------------------- Family Payment -------------------
def family_payment(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        if request.method == 'POST':
            form = FamilyPaymentForm(request.POST)
            if form.is_valid():
                cnic = form.cleaned_data['father_cnic']
                amount = form.cleaned_data['amount'] or None
                mode = form.cleaned_data['payment_mode']
                remarks = form.cleaned_data['remarks']
                students = Student.objects.filter(father_cnic=cnic, status='active')
                if not students.exists():
                    messages.error(request, "No student found with this CNIC.")
                    return redirect('family_payment', schema_name=schema_name)
                total_pending = 0
                all_pending_records = []
                for s in students:
                    records = s.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date')
                    total_pending += sum(r.remaining for r in records)
                    all_pending_records.extend(records)
                if amount is None:
                    amount = total_pending
                if amount > total_pending:
                    messages.error(request, f"Amount exceeds total pending ({total_pending})")
                    return redirect('family_payment', schema_name=schema_name)
                remaining = amount
                paid_records = []
                for record in all_pending_records:
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
                for student in students:
                    student_paid = [r for r in paid_records if r.student == student]
                    if student_paid:
                        payment = PaymentTransaction.objects.create(
                            student=student, amount=sum(r.paid_amount for r in student_paid),
                            payment_mode=mode, payment_type='full' if remaining == 0 else 'partial',
                            remarks=remarks, created_by=request.session.get('school_admin_username', 'admin')
                        )
                        payment.fee_records.set(student_paid)
                messages.success(request, f"Family payment of ₹{amount} processed for CNIC {cnic}")
                return redirect('reports', schema_name=schema_name)
        else:
            form = FamilyPaymentForm()
    context = {'tenant': tenant, 'form': form, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/family_payment.html', context)

# ------------------- Add Student -------------------
def add_student(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        if request.method == 'POST':
            form = StudentForm(request.POST)
            if form.is_valid():
                student = form.save(commit=False)
                if student.custom_fee == 0:
                    fee_struct = FeeStructure.objects.filter(grade=student.grade).first()
                    if fee_struct:
                        student.custom_fee = fee_struct.monthly_fee
                student.save()
                messages.success(request, f"Student {student.name} added successfully. Roll No: {student.roll_number}")
                return redirect('student_list', schema_name=schema_name)
        else:
            form = StudentForm()
        grades = FeeStructure.objects.values_list('grade', flat=True).distinct()
        context = {
            'tenant': tenant, 'form': form, 'grades': grades,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/student_form.html', context)

# ------------------- Edit Student -------------------
def edit_student(request, schema_name, student_id):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        if request.method == 'POST':
            form = StudentForm(request.POST, instance=student)
            if form.is_valid():
                form.save()
                messages.success(request, f"Student {student.name} updated successfully.")
                return redirect('student_profile', schema_name=schema_name, student_id=student.id)
        else:
            form = StudentForm(instance=student)
        grades = FeeStructure.objects.values_list('grade', flat=True).distinct()
        context = {
            'tenant': tenant, 'form': form, 'student': student, 'grades': grades,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/student_form.html', context)

# ------------------- API: Student Fee Records (JSON) -------------------
def student_fee_records_api(request, schema_name, student_id):
    """Return fee records for a student as JSON."""
    from django.http import JsonResponse
    from .models import Student, FeeRecord
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        records = student.fee_records.all().order_by('-year', '-month')
        data = [{
            'id': r.id,
            'month': r.month,
            'year': r.year,
            'amount': float(r.amount),
            'paid_amount': float(r.paid_amount),
            'remaining': float(r.remaining),
            'status': r.get_status_display(),
            'due_date': r.due_date.strftime('%Y-%m-%d'),
            'receipts': [{"id": p.id, "number": p.receipt_number} for p in r.payments.all()]
        } for r in records]
        return JsonResponse(data, safe=False)

# ------------------- API: Student Payment History (JSON) -------------------
def student_payments_api(request, schema_name, student_id):
    """Return payment transactions for a student as JSON."""
    from django.http import JsonResponse
    from .models import Student, PaymentTransaction
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        payments = student.payments.all().order_by('-payment_date')
        payments = list(payments)
        data = [{
            'id': p.id,
            'receipt_number': p.receipt_number,
            'amount': float(p.amount),
            'date': p.payment_date.strftime('%Y-%m-%d'),
            'mode': p.get_payment_mode_display(),
            'url': f'/portal/{schema_name}/fee/receipt/{p.id}/'
        } for p in payments]
        return JsonResponse(data, safe=False)
EOF

echo "✅ Missing view functions added successfully."
echo ""
echo "🚀 Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
