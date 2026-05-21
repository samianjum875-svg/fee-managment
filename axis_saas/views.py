from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.contrib import messages
from django.db.models import Sum, Q
from django.db import connection
from django_tenants.utils import schema_context
from decimal import Decimal
from datetime import date, timedelta
import json
from functools import wraps
from django.views.decorators.csrf import csrf_exempt
from django.utils import timezone
from django.views.decorators.http import require_http_methods

from .models import SchoolClient, Student, FeeStructure, FeeRecord, PaymentTransaction, SchoolFeeSettings
from .forms import StudentForm, FeeCollectionForm, FeeSettingsForm, FeeStructureForm, FamilyPaymentForm

# ------------------- Helper -------------------
def get_tenant(request, schema_name):
    return get_object_or_404(SchoolClient, schema_name=schema_name)

# ------------------- Dashboard -------------------
def dashboard(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        today = date.today()
        first_day_month = today.replace(day=1)
        
        today_collection = PaymentTransaction.objects.filter(payment_date=today).aggregate(Sum('amount'))['amount__sum'] or 0
        month_collection = PaymentTransaction.objects.filter(payment_date__gte=first_day_month).aggregate(Sum('amount'))['amount__sum'] or 0
        
        pending_records = FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue'])
        total_pending = sum(r.remaining for r in pending_records)
        defaulters_count = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct().count()
        recent_payments = PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:10]
        
        top_defaulters = []
        for student in Student.objects.all():
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            if pending > 0:
                top_defaulters.append({'student': student, 'pending': pending})
        top_defaulters = sorted(top_defaulters, key=lambda x: x['pending'], reverse=True)[:5]
        
        months_labels = []
        months_amounts = []
        for i in range(5, -1, -1):
            m = today.month - i
            y = today.year
            if m <= 0:
                m += 12
                y -= 1
            total = PaymentTransaction.objects.filter(payment_date__year=y, payment_date__month=m).aggregate(Sum('amount'))['amount__sum'] or 0
            months_labels.append(f"{m}/{y}")
            months_amounts.append(float(total))
    
    context = {
        'tenant': tenant,
        'today_collection': today_collection,
        'month_collection': month_collection,
        'total_pending': total_pending,
        'defaulters_count': defaulters_count,
        'recent_payments': recent_payments,
        'top_defaulters': top_defaulters,
        'months_labels': months_labels,
        'months_amounts': months_amounts,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        'today': today,
        'start_date': first_day_month,
    }
    return render(request, 'tenant/dashboard.html', context)

# ------------------- Student List -------------------
def student_list(request, schema_name):
    tenant = get_tenant(request, schema_name)
    query = request.GET.get('q', '')
    grade = request.GET.get('grade', '')
    section = request.GET.get('section', '')
    status = request.GET.get('status', '')
    
    with schema_context(schema_name):
        students = Student.objects.all()
        if query:
            students = students.filter(
                Q(name__icontains=query) | Q(roll_number__icontains=query) |
                Q(father_name__icontains=query) | Q(father_cnic__icontains=query) |
                Q(parent_mobile__icontains=query) | Q(grade__icontains=query)
            )
        if grade: students = students.filter(grade=grade)
        if section: students = students.filter(section=section)
        if status: students = students.filter(status=status)
        
        students = students.order_by('-enrolled_on')
        for s in students:
            s.pending_amount = sum(fr.remaining for fr in s.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
        
        grades = Student.objects.values_list('grade', flat=True).distinct().order_by('grade')
        sections = Student.objects.values_list('section', flat=True).distinct().order_by('section')
        status_choices = Student.STATUS_CHOICES
    
    context = {
        'tenant': tenant,
        'students': students,
        'grades': grades,
        'sections': sections,
        'status_choices': status_choices,
        'search_query': query,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/student_list.html', context)

# ------------------- Student Profile -------------------
def student_profile(request, schema_name, student_id):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        fee_records = student.fee_records.all().order_by('-year', '-month')
        payments = student.payments.all().order_by('-payment_date')
        total_fee = fee_records.aggregate(Sum('amount'))['amount__sum'] or 0
        total_paid = payments.aggregate(Sum('amount'))['amount__sum'] or 0
    
    context = {
        'tenant': tenant,
        'student': student,
        'fee_records': fee_records,
        'payments': payments,
        'total_fee': total_fee,
        'total_paid': total_paid,
        'pending_total': total_fee - total_paid,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/student_profile.html', context)

# ------------------- Fee Collection -------------------
def fee_collection(request, schema_name, student_id=None):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        today = date.today()
        today_collection = PaymentTransaction.objects.filter(payment_date=today).aggregate(Sum('amount'))['amount__sum'] or 0
        recent_payments = PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:10]
        total_pending_all = sum(fr.remaining for fr in FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue']))
        
        pending_students = []
        for student in Student.objects.filter(status='active'):
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            if pending > 0:
                pending_students.append({
                    'id': student.id,
                    'name': student.name,
                    'roll_number': student.roll_number,
                    'grade': student.grade,
                    'section': student.section,
                    'pending_total': pending
                })
        pending_students.sort(key=lambda x: x['pending_total'], reverse=True)
        
        if request.method == 'POST':
            student_id_post = request.POST.get('student_id')
            amount = Decimal(request.POST.get('amount', '0'))
            payment_mode = request.POST.get('payment_mode')
            remarks = request.POST.get('remarks', '')
            
            if not student_id_post or amount <= 0:
                messages.error(request, "Invalid payment data.")
                return redirect('fee_collection', schema_name=schema_name)
            
            student = get_object_or_404(Student, id=student_id_post)
            pending_records = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date')
            if not pending_records:
                messages.error(request, f"No pending fee for {student.name}.")
                return redirect('fee_collection', schema_name=schema_name)
            
            remaining = amount
            updated_records = []
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
                updated_records.append(record)
            
            payment_type = 'full' if remaining == 0 else 'partial'
            payment = PaymentTransaction.objects.create(
                student=student,
                amount=amount,
                payment_mode=payment_mode,
                payment_type=payment_type,
                remarks=remarks,
                created_by=request.session.get('school_admin_username', 'admin')
            )
            payment.fee_records.set(updated_records)
            messages.success(request, f"₹{amount} received from {student.name}. Receipt: {payment.receipt_number}")
            return redirect('fee_receipt', schema_name=schema_name, receipt_id=payment.id)
        
        selected_student = None
        pending_list = []
        if student_id:
            selected_student = get_object_or_404(Student, id=student_id)
            pending_list = selected_student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date')
        
        context = {
            'tenant': tenant,
            'selected_student': selected_student,
            'pending_records': pending_list,
            'total_pending': sum(r.remaining for r in pending_list),
            'today_collection': today_collection,
            'recent_payments': recent_payments,
            'total_pending_all': total_pending_all,
            'pending_students': pending_students,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
        return render(request, 'tenant/fee_collection.html', context)

# ------------------- Receipt -------------------
def fee_receipt(request, schema_name, receipt_id):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        payment = get_object_or_404(PaymentTransaction, id=receipt_id)
        context = {
            'tenant': tenant,
            'payment': payment,
            'fee_records': payment.fee_records.all(),
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
        return render(request, 'tenant/receipt.html', context)

# ------------------- Defaulters -------------------
def defaulters(request, schema_name):
    tenant = get_tenant(request, schema_name)
    days = request.GET.get('days', '30')
    try:
        days = int(days)
    except:
        days = 30
    if days > 3650:
        days = 3650
    
    with schema_context(schema_name):
        today = date.today()
        cutoff = today - timedelta(days=days)
        defaulters_list = Student.objects.filter(
            fee_records__status__in=['pending', 'partial', 'overdue'],
            fee_records__due_date__lte=cutoff
        ).distinct()
        
        result = []
        for student in defaulters_list:
            pending_fee = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            oldest_due = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date').first()
            result.append({
                'student': student,
                'pending_amount': pending_fee,
                'days_overdue': (today - oldest_due.due_date).days if oldest_due else 0
            })
        result.sort(key=lambda x: x['days_overdue'], reverse=True)
        total_pending_all = sum(fr.remaining for fr in FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue']))
    
    context = {
        'tenant': tenant,
        'defaulters': result,
        'days': days,
        'total_pending_all': total_pending_all,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/defaulters.html', context)

# ------------------- Reports -------------------
def reports(request, schema_name):
    tenant = get_tenant(request, schema_name)
    report_type = request.GET.get('type', 'collection')
    start_date_str = request.GET.get('start_date')
    end_date_str = request.GET.get('end_date')
    if start_date_str and end_date_str:
        start_date = date.fromisoformat(start_date_str)
        end_date = date.fromisoformat(end_date_str)
    else:
        end_date = date.today()
        start_date = end_date.replace(day=1)
    
    with schema_context(schema_name):
        payments_in_range = PaymentTransaction.objects.filter(payment_date__range=[start_date, end_date])
        total_collection = payments_in_range.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        pending_records = FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue'])
        total_pending = sum(r.remaining for r in pending_records)
        total_collection_all = PaymentTransaction.objects.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        total_billed = total_collection_all + total_pending
        collection_rate = (float(total_collection_all) / float(total_billed) * 100) if total_billed > 0 else 0
        defaulters_count = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct().count()
        
        monthly_data = []
        today = date.today()
        for i in range(5, -1, -1):
            m = today.month - i
            y = today.year
            if m <= 0:
                m += 12
                y -= 1
            total = PaymentTransaction.objects.filter(payment_date__year=y, payment_date__month=m).aggregate(Sum('amount'))['amount__sum'] or 0
            monthly_data.append({'month': f"{m}/{y}", 'amount': float(total)})
        
        mode_distribution = []
        mode_totals = {}
        for mode_code, mode_name in PaymentTransaction.PAYMENT_MODE_CHOICES:
            total = payments_in_range.filter(payment_mode=mode_code).aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
            if total > 0:
                mode_totals[mode_name] = float(total)
        mode_distribution = [{'name': k, 'amount': v} for k, v in mode_totals.items()]
        
        class_pending = []
        grades = Student.objects.values_list('grade', flat=True).distinct().order_by('grade')
        for grade in grades:
            students = Student.objects.filter(grade=grade)
            pending = sum(
                sum(fr.remaining for fr in s.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
                for s in students
            )
            if pending > 0:
                class_pending.append({'grade': grade, 'pending': float(pending)})
        class_pending.sort(key=lambda x: x['pending'], reverse=True)
        
        top_defaulters = []
        for student in Student.objects.all():
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            if pending > 0:
                top_defaulters.append({'student': student, 'pending': float(pending)})
        top_defaulters = sorted(top_defaulters, key=lambda x: x['pending'], reverse=True)[:5]
        
        defaulters_list = Student.objects.filter(
            fee_records__status__in=['pending', 'partial', 'overdue']
        ).distinct()
        defaulters_data = []
        for student in defaulters_list:
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            oldest_due = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date').first()
            defaulters_data.append({
                'student': student,
                'pending_amount': pending,
                'days_overdue': (date.today() - oldest_due.due_date).days if oldest_due else 0
            })
        defaulters_data.sort(key=lambda x: x['days_overdue'], reverse=True)
        
        context = {
            'tenant': tenant,
            'report_type': report_type,
            'start_date': start_date,
            'end_date': end_date,
            'total_collection': total_collection,
            'total_pending': total_pending,
            'collection_rate': round(collection_rate, 1),
            'defaulters_count': defaulters_count,
            'monthly_data': monthly_data,
            'mode_distribution': mode_distribution,
            'class_pending': class_pending,
            'top_defaulters': top_defaulters,
            'defaulters_data': defaulters_data,
            'payments': payments_in_range.order_by('-payment_date'),
            'total': total_collection,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/reports.html', context)

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
    context = {
        'tenant': tenant,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/settings.html', context)

# ------------------- Fee Structure -------------------
def fee_structure(request, schema_name):
    tenant = get_tenant(request, schema_name)
    edit_grade = request.GET.get('edit', '')
    with schema_context(schema_name):
        if request.method == 'POST':
            grade = request.POST.get('grade')
            monthly_fee = request.POST.get('monthly_fee')
            obj, created = FeeStructure.objects.update_or_create(
                grade=grade,
                defaults={'monthly_fee': monthly_fee}
            )
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
        'tenant': tenant,
        'form': form,
        'fee_structures': structures,
        'edit_grade': edit_grade,
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
    context = {
        'tenant': tenant,
        'form': form,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
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
                            student=student,
                            amount=sum(r.paid_amount for r in student_paid),
                            payment_mode=mode,
                            payment_type='full' if remaining == 0 else 'partial',
                            remarks=remarks,
                            created_by=request.session.get('school_admin_username', 'admin')
                        )
                        payment.fee_records.set(student_paid)
                messages.success(request, f"Family payment of ₹{amount} processed for CNIC {cnic}")
                return redirect('reports', schema_name=schema_name)
        else:
            form = FamilyPaymentForm()
    context = {
        'tenant': tenant,
        'form': form,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/family_payment.html', context)

# ------------------- API: Student Search -------------------
def student_search_api(request, schema_name):
    q = request.GET.get('q', '')
    with schema_context(schema_name):
        students = Student.objects.filter(
            Q(name__icontains=q) | Q(roll_number__icontains=q) | Q(father_name__icontains=q) | Q(father_cnic__icontains=q)
        )[:10]
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
        
        return JsonResponse({
            'last_generation': last_gen, 
            'next_generation': next_date.strftime('%Y-%m-%d'), 
            'status': 'success'
        })

# ------------------- API: Manual Generate -------------------
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
        
        # Check if already generated
        existing = FeeRecord.objects.filter(month=month, year=year)
        if existing.exists():
            return JsonResponse({'message': f'Fee records for {month}/{year} already exist. ({existing.count()} records)'})
        
        students = Student.objects.filter(status='active')
        due_date = today + timedelta(days=settings.due_date_offset)
        created = 0
        errors = []
        
        for student in students:
            base_fee = student.custom_fee if student.custom_fee > 0 else 0
            if base_fee == 0:
                fee_struct = FeeStructure.objects.filter(grade=student.grade).first()
                if fee_struct:
                    base_fee = fee_struct.monthly_fee
            
            if base_fee > 0:
                obj, is_new = FeeRecord.objects.get_or_create(
                    student=student, month=month, year=year,
                    defaults={'amount': base_fee, 'due_date': due_date, 'status': 'pending'}
                )
                if is_new:
                    created += 1
        
        return JsonResponse({'message': f'Generated {created} fee records for {month}/{year}.', 'created': created})

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
        
        if base_fee <= 0:
            return JsonResponse({'error': 'No fee structure defined for this grade.'}, status=400)
        
        due_date = today + timedelta(days=settings.due_date_offset)
        FeeRecord.objects.create(
            student=student, month=month, year=year,
            amount=base_fee, due_date=due_date, status='pending'
        )
        return JsonResponse({'message': f'Fee record created for {student.name} for {month}/{year}.'})

# ------------------- Add Student -------------------
def add_student(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        if request.method == 'POST':
            form = StudentForm(request.POST)
            if form.is_valid():
                student = form.save(commit=False)
                student.save()
                messages.success(request, f"Student {student.name} added successfully. Roll No: {student.roll_number}")
                return redirect('student_list', schema_name=schema_name)
        else:
            form = StudentForm()
        grades = FeeStructure.objects.values_list('grade', flat=True).distinct()
        context = {
            'tenant': tenant,
            'form': form,
            'grades': grades,
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
            'tenant': tenant,
            'form': form,
            'student': student,
            'grades': grades,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
        return render(request, 'tenant/student_form.html', context)
