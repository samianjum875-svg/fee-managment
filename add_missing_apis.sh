#!/bin/bash

# add_missing_apis.sh - Adds missing API views to axis_saas/views.py
# Run from: ~/axis_school_sys

set -e

VIEWS_FILE="axis_saas/views.py"

if [ ! -f "$VIEWS_FILE" ]; then
    echo "ERROR: $VIEWS_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup original
if [ ! -f "${VIEWS_FILE}.bak3" ]; then
    cp "$VIEWS_FILE" "${VIEWS_FILE}.bak3"
    echo "✅ Backup saved as ${VIEWS_FILE}.bak3"
fi

# Check if functions already exist
if grep -q "^def student_search_api(" "$VIEWS_FILE"; then
    echo "All API functions already present. Nothing to do."
    exit 0
fi

echo "✍️  Appending missing API functions to $VIEWS_FILE ..."

cat >> "$VIEWS_FILE" << 'EOF'

# ------------------- API: Student Search -------------------
def student_search_api(request, schema_name):
    q = request.GET.get('q', '')
    with schema_context(schema_name):
        students = Student.objects.filter(
            Q(name__icontains=q) | Q(roll_number__icontains=q) | Q(father_name__icontains=q) | Q(father_cnic__icontains=q)
        )[:5]
        data = [{'id': s.id, 'name': s.name, 'roll_no': s.roll_number, 'grade': s.grade} for s in students]
    return JsonResponse(data, safe=False)

# ------------------- API: Fee Status -------------------
@csrf_exempt
@require_http_methods(["GET"])
def fee_status_api(request):
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    schema_name = request.session.get('school_admin_schema')
    if not schema_name:
        return JsonResponse({'error': 'No tenant schema'}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({'error': 'Tenant not found'}, status=404)
    with schema_context(schema_name):
        settings, _ = SchoolFeeSettings.objects.get_or_create(pk=1)
        last_record = FeeRecord.objects.order_by('-year', '-month').first()
        last_gen = f"{last_record.month}/{last_record.year}" if last_record else "Never"
        today = date.today()
        gen_day = settings.fee_generation_day
        from calendar import monthrange
        if today.day <= gen_day:
            next_date = date(today.year, today.month, min(gen_day, monthrange(today.year, today.month)[1]))
        else:
            next_month = today.month + 1 if today.month < 12 else 1
            next_year = today.year + 1 if today.month == 12 else today.year
            next_date = date(next_year, next_month, min(gen_day, monthrange(next_year, next_month)[1]))
        return JsonResponse({'last_generation': last_gen, 'next_generation': next_date.strftime('%Y-%m-%d'), 'status': 'success'})

# ------------------- API: Manual Generate (All Students) -------------------
@csrf_exempt
@require_http_methods(["POST"])
def manual_generate_api(request):
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    schema_name = request.session.get('school_admin_schema')
    if not schema_name:
        return JsonResponse({'error': 'No tenant schema'}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({'error': 'Tenant not found'}, status=404)
    with schema_context(schema_name):
        settings, _ = SchoolFeeSettings.objects.get_or_create(pk=1)
        today = date.today()
        month = today.month
        year = today.year
        existing = FeeRecord.objects.filter(month=month, year=year)
        if existing.exists():
            return JsonResponse({'message': f'Fee records for {month}/{year} already exist. ({existing.count()} records)'})
        students = Student.objects.filter(status='active')
        if not students.exists():
            return JsonResponse({'message': 'No active students found. Please add students first.'})
        due_date = today + timedelta(days=settings.due_date_offset)
        created = 0
        skipped_no_fee = 0
        for student in students:
            base_fee = student.custom_fee if student.custom_fee > 0 else 0
            if base_fee == 0:
                fee_struct = FeeStructure.objects.filter(grade=student.grade).first()
                if fee_struct:
                    base_fee = fee_struct.monthly_fee
                    student.custom_fee = base_fee
                    student.save(update_fields=['custom_fee'])
            if base_fee > 0:
                obj, is_new = FeeRecord.objects.get_or_create(
                    student=student, month=month, year=year,
                    defaults={'amount': base_fee, 'due_date': due_date, 'status': 'pending'}
                )
                if is_new:
                    created += 1
            else:
                skipped_no_fee += 1
        message = f'Generated {created} fee records for {month}/{year}.'
        if skipped_no_fee > 0:
            message += f' Skipped {skipped_no_fee} students because no fee structure defined for their grade.'
        return JsonResponse({'message': message, 'created': created, 'skipped': skipped_no_fee})

# ------------------- API: Manual Generate for Single Student -------------------
@csrf_exempt
@require_http_methods(["POST"])
def manual_generate_single_api(request):
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    schema_name = request.session.get('school_admin_schema')
    if not schema_name:
        return JsonResponse({'error': 'No tenant schema'}, status=400)
    student_id = request.GET.get('student_id') or request.POST.get('student_id')
    if not student_id:
        return JsonResponse({'error': 'Student ID required'}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({'error': 'Tenant not found'}, status=404)
    with schema_context(schema_name):
        try:
            student = Student.objects.get(id=student_id)
        except Student.DoesNotExist:
            return JsonResponse({'error': 'Student not found'}, status=404)
        settings, _ = SchoolFeeSettings.objects.get_or_create(pk=1)
        today = date.today()
        month = today.month
        year = today.year
        if FeeRecord.objects.filter(student=student, month=month, year=year).exists():
            return JsonResponse({'message': f'Fee already exists for {student.name} for {month}/{year}.'})
        base_fee = student.custom_fee if student.custom_fee > 0 else 0
        if base_fee == 0:
            fee_struct = FeeStructure.objects.filter(grade=student.grade).first()
            if fee_struct:
                base_fee = fee_struct.monthly_fee
                student.custom_fee = base_fee
                student.save(update_fields=['custom_fee'])
        if base_fee <= 0:
            return JsonResponse({'error': 'No fee structure defined for this grade.'}, status=400)
        due_date = today + timedelta(days=settings.due_date_offset)
        FeeRecord.objects.create(
            student=student, month=month, year=year,
            amount=base_fee, due_date=due_date, status='pending'
        )
        return JsonResponse({'message': f'Fee record created for {student.name} for {month}/{year}.'})
EOF

echo "✅ Missing API functions added successfully."
echo ""
echo "🚀 Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
