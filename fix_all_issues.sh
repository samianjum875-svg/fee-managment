#!/bin/bash

# ============================================================
# 1. Fix missing view functions in axis_saas/views.py
# ============================================================
echo "Checking for missing view functions..."

# Backup views.py
cp axis_saas/views.py axis_saas/views.py.bak 2>/dev/null

# Function to check if a function exists
function ensure_function() {
    local func_name="$1"
    local func_code="$2"
    if ! grep -q "def $func_name" axis_saas/views.py; then
        echo "Adding missing function: $func_name"
        echo "$func_code" >> axis_saas/views.py
    else
        echo "Function $func_name already exists."
    fi
}

# Define missing functions (based on import error)
# Note: These are the exact implementations from your original code
ensure_function "student_search_api" '
# ------------------- API: Student Search -------------------
def student_search_api(request, schema_name):
    q = request.GET.get("q", "")
    with schema_context(schema_name):
        students = Student.objects.filter(
            Q(name__icontains=q) | Q(roll_number__icontains=q) | Q(father_name__icontains=q) | Q(father_cnic__icontains=q)
        )[:5]
        data = [{"id": s.id, "name": s.name, "roll_no": s.roll_number, "grade": s.grade} for s in students]
    return JsonResponse(data, safe=False)
'

ensure_function "add_student" '
# ------------------- Add Student -------------------
def add_student(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        if request.method == "POST":
            form = StudentForm(request.POST)
            if form.is_valid():
                student = form.save(commit=False)
                if student.custom_fee == 0:
                    fee_struct = FeeStructure.objects.filter(grade=student.grade).first()
                    if fee_struct:
                        student.custom_fee = fee_struct.monthly_fee
                student.save()
                messages.success(request, f"Student {student.name} added successfully. Roll No: {student.roll_number}")
                return redirect("student_list", schema_name=schema_name)
        else:
            form = StudentForm()
        grades = FeeStructure.objects.values_list("grade", flat=True).distinct()
        context = {
            "tenant": tenant, "form": form, "grades": grades,
            "logo_url": tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, "tenant/student_form.html", context)
'

ensure_function "edit_student" '
# ------------------- Edit Student -------------------
def edit_student(request, schema_name, student_id):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        if request.method == "POST":
            form = StudentForm(request.POST, instance=student)
            if form.is_valid():
                form.save()
                messages.success(request, f"Student {student.name} updated successfully.")
                return redirect("student_profile", schema_name=schema_name, student_id=student.id)
        else:
            form = StudentForm(instance=student)
        grades = FeeStructure.objects.values_list("grade", flat=True).distinct()
        context = {
            "tenant": tenant, "form": form, "student": student, "grades": grades,
            "logo_url": tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, "tenant/student_form.html", context)
'

ensure_function "fee_status_api" '
# ------------------- API: Fee Status -------------------
@csrf_exempt
@require_http_methods(["GET"])
def fee_status_api(request):
    if not request.session.get("school_admin_authenticated"):
        return JsonResponse({"error": "Unauthorized"}, status=401)
    schema_name = request.session.get("school_admin_schema")
    if not schema_name:
        return JsonResponse({"error": "No tenant schema"}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({"error": "Tenant not found"}, status=404)
    with schema_context(schema_name):
        settings, _ = SchoolFeeSettings.objects.get_or_create(pk=1)
        last_record = FeeRecord.objects.order_by("-year", "-month").first()
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
        return JsonResponse({"last_generation": last_gen, "next_generation": next_date.strftime("%Y-%m-%d"), "status": "success"})
'

ensure_function "manual_generate_api" '
# ------------------- API: Manual Generate (All Students) -------------------
@csrf_exempt
@require_http_methods(["POST"])
def manual_generate_api(request):
    if not request.session.get("school_admin_authenticated"):
        return JsonResponse({"error": "Unauthorized"}, status=401)
    schema_name = request.session.get("school_admin_schema")
    if not schema_name:
        return JsonResponse({"error": "No tenant schema"}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({"error": "Tenant not found"}, status=404)
    with schema_context(schema_name):
        settings, _ = SchoolFeeSettings.objects.get_or_create(pk=1)
        today = date.today()
        month = today.month
        year = today.year
        existing = FeeRecord.objects.filter(month=month, year=year)
        if existing.exists():
            return JsonResponse({"message": f"Fee records for {month}/{year} already exist. ({existing.count()} records)"})
        students = Student.objects.filter(status="active")
        if not students.exists():
            return JsonResponse({"message": "No active students found. Please add students first."})
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
                    student.save(update_fields=["custom_fee"])
            if base_fee > 0:
                obj, is_new = FeeRecord.objects.get_or_create(
                    student=student, month=month, year=year,
                    defaults={"amount": base_fee, "due_date": due_date, "status": "pending"}
                )
                if is_new:
                    created += 1
            else:
                skipped_no_fee += 1
        message = f"Generated {created} fee records for {month}/{year}."
        if skipped_no_fee > 0:
            message += f" Skipped {skipped_no_fee} students because no fee structure defined for their grade."
        return JsonResponse({"message": message, "created": created, "skipped": skipped_no_fee})
'

ensure_function "manual_generate_single_api" '
# ------------------- API: Manual Generate for Single Student -------------------
@csrf_exempt
@require_http_methods(["POST"])
def manual_generate_single_api(request):
    if not request.session.get("school_admin_authenticated"):
        return JsonResponse({"error": "Unauthorized"}, status=401)
    schema_name = request.session.get("school_admin_schema")
    if not schema_name:
        return JsonResponse({"error": "No tenant schema"}, status=400)
    student_id = request.GET.get("student_id") or request.POST.get("student_id")
    if not student_id:
        return JsonResponse({"error": "Student ID required"}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({"error": "Tenant not found"}, status=404)
    with schema_context(schema_name):
        try:
            student = Student.objects.get(id=student_id)
        except Student.DoesNotExist:
            return JsonResponse({"error": "Student not found"}, status=404)
        settings, _ = SchoolFeeSettings.objects.get_or_create(pk=1)
        today = date.today()
        month = today.month
        year = today.year
        if FeeRecord.objects.filter(student=student, month=month, year=year).exists():
            return JsonResponse({"message": f"Fee already exists for {student.name} for {month}/{year}."})
        base_fee = student.custom_fee if student.custom_fee > 0 else 0
        if base_fee == 0:
            fee_struct = FeeStructure.objects.filter(grade=student.grade).first()
            if fee_struct:
                base_fee = fee_struct.monthly_fee
                student.custom_fee = base_fee
                student.save(update_fields=["custom_fee"])
        if base_fee <= 0:
            return JsonResponse({"error": "No fee structure defined for this grade."}, status=400)
        due_date = today + timedelta(days=settings.due_date_offset)
        FeeRecord.objects.create(
            student=student, month=month, year=year,
            amount=base_fee, due_date=due_date, status="pending"
        )
        return JsonResponse({"message": f"Fee record created for {student.name} for {month}/{year}."})
'

ensure_function "student_fee_records_api" '
# ------------------- API: Student Fee Records (JSON) -------------------
def student_fee_records_api(request, schema_name, student_id):
    """Return fee records for a student as JSON."""
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        records = student.fee_records.all().order_by("-year", "-month")
        data = [{
            "id": r.id,
            "month": r.month,
            "year": r.year,
            "amount": float(r.amount),
            "paid_amount": float(r.paid_amount),
            "remaining": float(r.remaining),
            "status": r.get_status_display(),
            "due_date": r.due_date.strftime("%Y-%m-%d"),
            "receipts": [{"id": p.id, "number": p.receipt_number} for p in r.payments.all()]
        } for r in records]
        return JsonResponse(data, safe=False)
'

ensure_function "student_payments_api" '
# ------------------- API: Student Payment History (JSON) -------------------
def student_payments_api(request, schema_name, student_id):
    """Return payment transactions for a student as JSON."""
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        payments = student.payments.all().order_by("-payment_date")
        payments = list(payments)
        data = [{
            "id": p.id,
            "receipt_number": p.receipt_number,
            "amount": float(p.amount),
            "date": p.payment_date.strftime("%Y-%m-%d"),
            "mode": p.get_payment_mode_display(),
            "url": f"/portal/{schema_name}/fee/receipt/{p.id}/"
        } for p in payments]
        return JsonResponse(data, safe=False)
'

echo "✅ All missing view functions have been added."

# ============================================================
# 2. Fix fee_structure.html (remove duplicate info-panel)
# ============================================================
echo "Fixing fee_structure.html template..."

cat > templates/tenant/fee_structure.html << 'EOF'
{% extends 'tenant/base.html' %}
{% load static %}
{% block title %}Fee Structure | {{ tenant.name }}{% endblock %}
{% block body %}
<div class="page-header">
    <div>
        <h1 class="page-title">Fee Structure</h1>
        <p class="page-desc">Set monthly fee per class/grade</p>
    </div>
</div>

<!-- Add/Edit Form -->
<div class="page-card">
    <h3 style="margin-bottom: 20px;">
        {% if edit_grade %}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/>
                <path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4Z"/>
            </svg>
            Edit Fee for {{ edit_grade }}
        {% else %}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M12 4v16m8-8H4"/>
            </svg>
            Add New Fee Structure
        {% endif %}
    </h3>
    <form method="post" id="feeForm">
        {% csrf_token %}
        <div class="field-card">
            <label>Class/Grade</label>
            <input type="text" name="grade" id="grade" value="{{ form.grade.value|default:'' }}" required {% if edit_grade %}readonly{% endif %}>
        </div>
        <div class="field-card">
            <label>Monthly Fee (₹)</label>
            <input type="number" step="0.01" name="monthly_fee" id="monthly_fee" value="{{ form.monthly_fee.value|default:'' }}" required>
        </div>
        <div style="margin-top: 20px; display: flex; gap: 10px; flex-wrap: wrap;">
            <button type="submit" class="btn-primary">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/>
                </svg>
                {% if edit_grade %}Update Fee{% else %}Save Fee{% endif %}
            </button>
            {% if edit_grade %}
                <a href="{% url 'fee_structure' schema_name=tenant.schema_name %}" class="btn-secondary">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M6 18L18 6M6 6l12 12"/></svg>
                    Cancel Edit
                </a>
            {% endif %}
        </div>
    </form>
</div>

<!-- Current Fee Structures Table -->
<div class="page-card">
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; flex-wrap: wrap; gap: 10px;">
        <h3 style="margin:0;">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M3 6h18M9 12h6M7 18h10"/>
            </svg>
            Current Fee Structure
        </h3>
        <div style="width: 250px;">
            <div style="position: relative;">
                <svg style="position: absolute; left: 10px; top: 50%; transform: translateY(-50%); width: 16px; height: 16px;" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                    <circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>
                </svg>
                <input type="text" id="searchTable" placeholder="Search class..." style="width:100%; padding: 8px 12px 8px 36px; border-radius: 6px; border: 1px solid var(--border); background: var(--surface-alt);">
            </div>
        </div>
    </div>
    <div style="overflow-x: auto;">
        <table class="data-table" id="feeTable" style="width:100%; min-width: 400px;">
            <thead>
                <tr>
                    <th>Class/Grade</th>
                    <th>Monthly Fee (₹)</th>
                    <th>Last Updated</th>
                    <th style="width: 150px;">Actions</th>
                </tr>
            </thead>
            <tbody>
                {% for fs in fee_structures %}
                <tr>
                    <td><strong>{{ fs.grade }}</strong></td>
                    <td>₹{{ fs.monthly_fee|floatformat:2 }}</td>
                    <td>{{ fs.updated_at|date:"Y-m-d H:i" }}</td>
                    <td style="display: flex; gap: 8px; flex-wrap: wrap;">
                        <a href="{% url 'fee_structure' schema_name=tenant.schema_name %}?edit={{ fs.grade }}" class="btn-small edit-btn" title="Edit">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/>
                                <path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4Z"/>
                            </svg>
                            Edit
                        </a>
                        <a href="{% url 'student_list' schema_name=tenant.schema_name %}?grade={{ fs.grade }}" class="btn-small view-btn" target="_blank" title="View Students">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/>
                            </svg>
                            View Students
                        </a>
                    </td>
                </tr>
                {% empty %}
                <tr><td colspan="4" style="text-align: center; padding: 2rem; color: var(--muted);">
                    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                        <circle cx="12" cy="12" r="10"/>
                        <path d="M12 8v4m0 4h.01"/>
                    </svg>
                    <p>No fee structures defined yet. Use the form above to add one.</p>
                </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
    {% if fee_structures %}
    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.5rem; border-radius: 0.5rem; font-size:0.8rem; display: inline-flex; align-items: center; gap: 0.5rem;">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>
        <span>{{ fee_structures|length }} fee structure(s) loaded.</span>
        {% if debug_count != fee_structures|length %}
        <span style="color: #f97316;">(debug: {{ debug_count }})</span>
        {% endif %}
    </div>
    {% else %}
    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.75rem; border-radius: 0.5rem;">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 8v4m0 4h.01"/></svg>
        <span>After adding a fee structure, all students in that grade will automatically get the monthly fee. You can also set a custom fee per student.</span>
    </div>
    {% endif %}
</div>

<style>
.btn-primary {
    background: var(--primary);
    color: white;
    padding: 10px 20px;
    border-radius: 6px;
    border: none;
    font-weight: 600;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    transition: background 0.2s;
}
.btn-primary:hover { background: var(--primary-dark); }
.btn-secondary {
    background: var(--surface-alt);
    color: var(--text);
    padding: 10px 20px;
    border-radius: 6px;
    border: 1px solid var(--border);
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
}
.btn-small {
    padding: 6px 12px;
    border-radius: 4px;
    font-size: 0.8rem;
    text-decoration: none;
    display: inline-flex;
    align-items: center;
    gap: 6px;
}
.edit-btn { background: var(--primary); color: white; }
.view-btn { background: var(--surface-alt); color: var(--text); border: 1px solid var(--border); }
.data-table {
    width: 100%;
    border-collapse: collapse;
}
.data-table th, .data-table td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid var(--border);
}
.data-table th {
    background: var(--surface-alt);
    font-weight: 600;
    color: var(--muted);
    text-transform: uppercase;
    font-size: 0.75rem;
}
.field-card {
    margin-bottom: 1rem;
}
.field-card label {
    display: block;
    font-weight: 600;
    margin-bottom: 0.3rem;
}
.field-card input, .field-card select {
    width: 100%;
    padding: 10px 12px;
    border-radius: 6px;
    border: 1px solid var(--border);
    background: var(--surface-alt);
    color: var(--text);
}
.page-card {
    background: var(--surface);
    border-radius: var(--radius);
    border: 1px solid var(--border);
    padding: 1.5rem;
    margin-bottom: 1.5rem;
    box-shadow: var(--shadow);
}
.info-panel {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.85rem;
}
@media (max-width: 600px) {
    .data-table th, .data-table td {
        padding: 8px;
    }
    .btn-small {
        padding: 4px 8px;
        font-size: 0.7rem;
    }
}
</style>

<script>
    // Live search in the fee table
    const searchInput = document.getElementById('searchTable');
    if (searchInput) {
        searchInput.addEventListener('keyup', function() {
            let filter = this.value.toLowerCase();
            let rows = document.querySelectorAll('#feeTable tbody tr');
            rows.forEach(row => {
                let grade = row.cells[0].innerText.toLowerCase();
                row.style.display = grade.includes(filter) ? '' : 'none';
            });
        });
    }
</script>
{% endblock %}
EOF

echo "✅ fee_structure.html has been cleaned up (duplicate panel removed)."

# ============================================================
# Final instructions
# ============================================================
echo ""
echo "==========================================================="
echo "All fixes applied successfully!"
echo "==========================================================="
echo "👉 Restart your Django server now:"
echo "   python3 manage.py runserver"
echo "👉 Then hard refresh the browser (Ctrl+Shift+R)."
echo "==========================================================="
EOF
