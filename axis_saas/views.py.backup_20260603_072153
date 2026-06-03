from django.shortcuts import render, redirect, get_object_or_404
from django.http import JsonResponse
from django.contrib import messages
from django.db.models import Sum, Q
from django.db.models.functions import TruncMonth, TruncDay
from django.db.models import Count
from django.core.paginator import Paginator
from django.db import connection
from django_tenants.utils import schema_context
from decimal import Decimal
from datetime import date, timedelta
from collections import defaultdict
import json
from functools import wraps
from django.views.decorators.csrf import csrf_exempt
from django.utils import timezone
from django.views.decorators.http import require_http_methods

from .models import SchoolClient, Student, FeeStructure, FeeRecord, PaymentTransaction, SchoolFeeSettings
from .forms import StudentForm, FeeCollectionForm, FeeSettingsForm, FeeStructureForm, FamilyPaymentForm

def get_tenant(request, schema_name):
    return get_object_or_404(SchoolClient, schema_name=schema_name)

# ------------------- Dashboard -------------------
def dashboard(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        today = timezone.localdate()
        first_day_month = today.replace(day=1)
        today_collection = PaymentTransaction.objects.filter(payment_date=today).aggregate(Sum('amount'))['amount__sum'] or 0
        month_collection = PaymentTransaction.objects.filter(payment_date__gte=first_day_month).aggregate(Sum('amount'))['amount__sum'] or 0
        pending_records = FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue'])
        total_pending = sum(r.remaining for r in pending_records)
        defaulters_count = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct().count()
        total_payments_count = PaymentTransaction.objects.count()
        recent_payments = PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:5]
        recent_payments = list(recent_payments)
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
        'tenant': tenant, 'today_collection': today_collection, 'month_collection': month_collection,
        'total_pending': total_pending, 'defaulters_count': defaulters_count,
        'recent_payments': recent_payments, 'top_defaulters': top_defaulters,
        'months_labels': months_labels, 'months_amounts': months_amounts,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        'today': today, 'start_date': first_day_month,
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
        grades = list(grades)
        sections = Student.objects.values_list('section', flat=True).distinct().order_by('section')
        sections = list(sections)
        status_choices = Student.STATUS_CHOICES
    context = {
        'tenant': tenant, 'students': students, 'grades': grades, 'sections': sections,
        'status_choices': status_choices, 'search_query': query,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/student_list.html', context)

# ------------------- Student Profile -------------------
def student_profile(request, schema_name, student_id):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        student = get_object_or_404(Student, id=student_id)
        fee_records_qs = student.fee_records.all().order_by('-year', '-month')
        total_fee = fee_records_qs.aggregate(Sum('amount'))['amount__sum'] or 0
        fee_records = list(fee_records_qs)
        payments_qs = student.payments.all().order_by('-payment_date')
        total_paid = payments_qs.aggregate(Sum('amount'))['amount__sum'] or 0
        payments = list(payments_qs)
        pending_total = total_fee - total_paid
    context = {
        'tenant': tenant, 'student': student, 'fee_records': fee_records, 'payments': payments,
        'total_fee': total_fee, 'total_paid': total_paid, 'pending_total': pending_total,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/student_profile.html', context)

def fee_receipt(request, schema_name, receipt_id):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        payment = get_object_or_404(PaymentTransaction.objects.select_related('student'), id=receipt_id)
        fee_records = list(payment.fee_records.all())
        context = {
            'tenant': tenant,
            'payment': payment,
            'fee_records': fee_records,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/receipt.html', context)
def defaulters(request, schema_name):
    tenant = get_tenant(request, schema_name)
    days = request.GET.get('days', '0')
    try:
        days = int(days)
    except:
        days = 0
    if days < 0: days = 0
    with schema_context(schema_name):
        today = timezone.localdate()
        cutoff = today - timedelta(days=days) if days > 0 else None
        base_qs = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct()
        if cutoff:
            base_qs = base_qs.filter(fee_records__due_date__lte=cutoff)
        result = []
        for student in base_qs:
            pending_fee = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            oldest_due = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date').first()
            days_overdue = (today - oldest_due.due_date).days if oldest_due and oldest_due.due_date < today else 0
            result.append({'student': student, 'pending_amount': pending_fee, 'days_overdue': days_overdue})
        result.sort(key=lambda x: x['days_overdue'], reverse=True)
        total_pending_all = sum(fr.remaining for fr in FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue']))
    context = {
        'tenant': tenant, 'defaulters': result, 'days': days, 'total_pending_all': total_pending_all,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
    }
    return render(request, 'tenant/defaulters.html', context)

# ------------------- Reports -------------------
def reports(request, schema_name):
    tenant = get_tenant(request, schema_name)
    report_type = request.GET.get('type', 'collection')
    today = timezone.localdate()
    quick_filter = request.GET.get('quick_filter')
    start_date_str = request.GET.get('start_date')
    end_date_str = request.GET.get('end_date')
    search_q = request.GET.get('search', '').strip()
    page_num = request.GET.get('page', 1)

    # Determine date range
    if quick_filter == 'today':
        start_date = end_date = today
    elif quick_filter == 'week':
        start_date = today - timedelta(days=today.weekday())
        end_date = start_date + timedelta(days=6)
    elif quick_filter == 'month':
        start_date = today.replace(day=1)
        end_date = today
    elif quick_filter == 'year':
        start_date = today.replace(month=1, day=1)
        end_date = today
    elif quick_filter == 'all':
        start_date = date(2000, 1, 1)
        end_date = today
    elif quick_filter == 'last6months':
        start_date = today - timedelta(days=180)
        end_date = today
    elif start_date_str and end_date_str:
        try:
            start_date = date.fromisoformat(start_date_str)
            end_date = date.fromisoformat(end_date_str)
            if start_date > end_date:
                start_date, end_date = end_date, start_date
            quick_filter = 'custom'
        except:
            start_date = today - timedelta(days=180)
            end_date = today
            quick_filter = 'last6months'
    else:
        start_date = date(2000, 1, 1)
        end_date = today
        quick_filter = 'all'

    with schema_context(schema_name):
        payments_qs = PaymentTransaction.objects.filter(payment_date__gte=start_date, payment_date__lte=end_date)
        if search_q:
            payments_qs = payments_qs.filter(
                Q(receipt_number__icontains=search_q) |
                Q(student__name__icontains=search_q) |
                Q(student__roll_number__icontains=search_q)
            )

        paginator = Paginator(payments_qs.order_by('-payment_date'), 15)
        payments_page = paginator.get_page(page_num)

        total_collection = payments_qs.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        payment_count = payments_qs.count()

        pending_records = FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue'])
        total_pending = sum(r.remaining for r in pending_records)

        total_collection_all = PaymentTransaction.objects.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        total_billed = total_collection_all + total_pending
        collection_rate = (float(total_collection_all) / float(total_billed) * 100) if total_billed > 0 else 0

        defaulters_count = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct().count()

        monthly_data = []
        for i in range(5, -1, -1):
            m = today.month - i
            y = today.year
            if m <= 0:
                m += 12
                y -= 1
            total = PaymentTransaction.objects.filter(payment_date__year=y, payment_date__month=m).aggregate(Sum('amount'))['amount__sum'] or 0
            monthly_data.append({'month': f"{m}/{y}", 'amount': float(total)})

        mode_totals = {}
        for mode_code, mode_name in PaymentTransaction.PAYMENT_MODE_CHOICES:
            total = payments_qs.filter(payment_mode=mode_code).aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
            if total > 0:
                mode_totals[mode_name] = float(total)
        mode_distribution = [{'name': k, 'amount': v} for k, v in mode_totals.items()]

        class_pending = []
        grades = Student.objects.values_list('grade', flat=True).distinct().order_by('grade')
        grades = list(grades)
        for grade in grades:
            students = Student.objects.filter(grade=grade)
            pending = sum(sum(fr.remaining for fr in s.fee_records.filter(status__in=['pending', 'partial', 'overdue'])) for s in students)
            if pending > 0:
                class_pending.append({'grade': grade, 'pending': float(pending)})
        class_pending.sort(key=lambda x: x['pending'], reverse=True)

        top_defaulters = []
        for student in Student.objects.all():
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            if pending > 0:
                top_defaulters.append({'student': student, 'pending': float(pending)})
        top_defaulters = sorted(top_defaulters, key=lambda x: x['pending'], reverse=True)[:5]

        defaulters_list = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct()
        defaulters_data = []
        for student in defaulters_list:
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            oldest_due = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date').first()
            days_overdue = (timezone.localdate() - oldest_due.due_date).days if oldest_due and oldest_due.due_date < timezone.localdate() else 0
            defaulters_data.append({
                'student': student,
                'pending_amount': pending,
                'days_overdue': days_overdue
            })
        defaulters_data.sort(key=lambda x: x['days_overdue'], reverse=True)

        context = {
            'tenant': tenant,
            'report_type': report_type,
            'start_date': start_date,
            'end_date': end_date,
            'quick_filter': quick_filter,
            'search_query': search_q,
            'total_collection': total_collection,
            'total_pending': total_pending,
            'collection_rate': round(collection_rate, 1),
            'defaulters_count': defaulters_count,
            'monthly_data': monthly_data,
            'mode_distribution': mode_distribution,
            'class_pending': class_pending,
            'top_defaulters': top_defaulters,
            'defaulters_data': defaulters_data,
            'payments': payments_page,
            'total': total_collection,
            'payment_count': payment_count,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
            'total_collection_all': total_collection_all,
        }
    return render(request, 'tenant/reports.html', context)

def fee_collection(request, schema_name, student_id=None):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        # Handle POST payment
        if request.method == 'POST':
            student_id_post = request.POST.get('student_id')
            amount = request.POST.get('amount')
            payment_mode = request.POST.get('payment_mode')
            remarks = request.POST.get('remarks', '')
            if student_id_post and amount:
                try:
                    student = Student.objects.get(id=student_id_post)
                    amount = Decimal(amount)
                    # Get pending records for this student
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
                    # Create payment transaction
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
                    return redirect('fee_collection', schema_name=schema_name, student_id=student.id)
                except Student.DoesNotExist:
                    messages.error(request, "Student not found")
                except Exception as e:
                    messages.error(request, f"Error processing payment: {str(e)}")
            else:
                messages.error(request, "Invalid payment data")
            return redirect('fee_collection', schema_name=schema_name)

        # GET request - prepare filters and student data
        search_filter = request.GET.get('pending_search', '')
        grade_filter = request.GET.get('pending_grade', '')
        section_filter = request.GET.get('pending_section', '')
        page_number = request.GET.get('page', 1)

        # Get all students with pending fees (aggregated)
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

        # Annotate pending total
        pending_students = []
        for s in students_qs:
            pending = sum(fr.remaining for fr in s.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            if pending > 0:
                s.pending_total = pending
                pending_students.append(s)
        pending_students.sort(key=lambda x: x.pending_total, reverse=True)

        # Pagination
        paginator = Paginator(pending_students, 20)
        pending_page = paginator.get_page(page_number)

        # Selected student details if student_id provided
        selected_student = None
        total_pending = 0
        pending_records = []
        if student_id:
            try:
                selected_student = Student.objects.get(id=student_id)
                pending_records = selected_student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date')
                total_pending = sum(r.remaining for r in pending_records)
            except Student.DoesNotExist:
                pass

        # Recent payments
        recent_payments = list(PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:5])
        total_pending_all = sum(fr.remaining for fr in FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue']))
        total_payments_count = PaymentTransaction.objects.count()
        grades = list(Student.objects.values_list('grade', flat=True).distinct().order_by('grade'))
        sections = list(Student.objects.values_list('section', flat=True).distinct().order_by('section'))

        context = {
            'tenant': tenant,
            'pending_students': pending_page,
            'selected_student': selected_student,
            'total_pending': total_pending,
            'pending_records': pending_records,
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
        return render(request, 'tenant/fee_collection.html', context)

@csrf_exempt
@require_http_methods(["GET"])
def debug_payments_api(request):
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
        payments = PaymentTransaction.objects.all().order_by('-payment_date')[:10]
        data = [{
            'id': p.id,
            'receipt_number': p.receipt_number,
            'student_id': p.student_id,
            'amount': float(p.amount),
            'date': p.payment_date.strftime('%Y-%m-%d')
        } for p in payments]
        return JsonResponse({'payments': data, 'total': PaymentTransaction.objects.count()})

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
            if grade and monthly_fee:
                obj, created = FeeStructure.objects.update_or_create(
                    grade=grade,
                    defaults={'monthly_fee': monthly_fee}
                )
                Student.objects.filter(grade=grade).update(custom_fee=monthly_fee)
                messages.success(request, f"Fee structure for {grade} saved successfully.")
            else:
                messages.error(request, "Please provide both grade and monthly fee.")
            return redirect('fee_structure', schema_name=schema_name)

        # CRITICAL FIX: evaluate queryset inside schema_context (convert to list)
        structures = list(FeeStructure.objects.all().order_by('grade'))
        print(f"[DEBUG] Tenant {schema_name}: found {len(structures)} fee structure(s)")
        for fs in structures:
            print(f"  - {fs.grade}: ₹{fs.monthly_fee}")

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
        'debug_count': len(structures),
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

# ------------------- API: Student Search -------------------
def student_search_api(request, schema_name):
    q = request.GET.get("q", "")
    with schema_context(schema_name):
        students = Student.objects.filter(
            Q(name__icontains=q) | Q(roll_number__icontains=q) | Q(father_name__icontains=q) | Q(father_cnic__icontains=q)
        )[:5]
        data = [{"id": s.id, "name": s.name, "roll_no": s.roll_number, "grade": s.grade} for s in students]
    return JsonResponse(data, safe=False)


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
        today = timezone.localdate()
        gen_day = settings.fee_generation_day
        from calendar import monthrange
        if today.day <= gen_day:
            next_date = date(today.year, today.month, min(gen_day, monthrange(today.year, today.month)[1]))
        else:
            next_month = today.month + 1 if today.month < 12 else 1
            next_year = today.year + 1 if today.month == 12 else today.year
            next_date = date(next_year, next_month, min(gen_day, monthrange(next_year, next_month)[1]))
        return JsonResponse({"last_generation": last_gen, "next_generation": next_date.strftime("%Y-%m-%d"), "status": "success"})


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
        today = timezone.localdate()
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
        today = timezone.localdate()
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



# ==================== GYM VIEWS ====================

def gym_dashboard(request, schema_name):
    tenant = get_tenant(request, schema_name)
    from .models import GymCustomer, GymPayment, GymAttendance, GymSubscription
    from datetime import date, timedelta
    with schema_context(schema_name):
        today = timezone.localdate()
        first_day_month = today.replace(day=1)
        today_checkins = GymAttendance.objects.filter(date=today).count()
        active_customers = GymCustomer.objects.filter(status='active').count()
        month_revenue = GymPayment.objects.filter(payment_date__gte=first_day_month).aggregate(Sum('amount'))['amount__sum'] or 0
        expiring_soon = GymCustomer.objects.filter(membership_end__gte=today, membership_end__lte=today+timedelta(days=7)).count()
        recent_payments = list(GymPayment.objects.select_related('customer').order_by('-payment_date')[:5])
        months_labels = []
        months_amounts = []
        for i in range(5, -1, -1):
            m = today.month - i
            y = today.year
            if m <= 0:
                m += 12
                y -= 1
            total = GymPayment.objects.filter(payment_date__year=y, payment_date__month=m).aggregate(Sum('amount'))['amount__sum'] or 0
            months_labels.append(f"{m}/{y}")
            months_amounts.append(float(total))
        context = {
            'tenant': tenant, 'today_checkins': today_checkins, 'active_customers': active_customers,
            'month_revenue': month_revenue, 'expiring_soon': expiring_soon,
            'recent_payments': recent_payments, 'months_labels': months_labels, 'months_amounts': months_amounts,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/gym_dashboard.html', context)

def gym_customer_list(request, schema_name):
    tenant = get_tenant(request, schema_name)
    query = request.GET.get('q', '')
    status = request.GET.get('status', '')
    with schema_context(schema_name):
        from .models import GymCustomer
        customers = GymCustomer.objects.all()
        if query:
            customers = customers.filter(name__icontains=query) | customers.filter(phone__icontains=query)
        if status:
            customers = customers.filter(status=status)
        customers = customers.order_by('-created_on')
        for c in customers:
            pending = sum(s.remaining for s in c.subscriptions.filter(status__in=['pending','partial','overdue']))
            c.pending_amount = pending
        status_choices = GymCustomer.STATUS_CHOICES
        context = {'tenant': tenant, 'customers': customers, 'status_choices': status_choices, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/gym_customer_list.html', context)

def gym_customer_add(request, schema_name):
    tenant = get_tenant(request, schema_name)
    from .forms import GymCustomerForm
    with schema_context(schema_name):
        if request.method == 'POST':
            form = GymCustomerForm(request.POST, request.FILES)
            if form.is_valid():
                customer = form.save()
                messages.success(request, f"Customer {customer.name} added.")
                return redirect('gym_customer_list', schema_name=schema_name)
        else:
            form = GymCustomerForm()
        context = {'tenant': tenant, 'form': form, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/gym_customer_form.html', context)

def gym_customer_edit(request, schema_name, customer_id):
    tenant = get_tenant(request, schema_name)
    from .forms import GymCustomerForm
    from .models import GymCustomer
    with schema_context(schema_name):
        customer = get_object_or_404(GymCustomer, id=customer_id)
        if request.method == 'POST':
            form = GymCustomerForm(request.POST, request.FILES, instance=customer)
            if form.is_valid():
                form.save()
                messages.success(request, "Customer updated.")
                return redirect('gym_customer_list', schema_name=schema_name)
        else:
            form = GymCustomerForm(instance=customer)
        context = {'tenant': tenant, 'form': form, 'customer': customer, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/gym_customer_form.html', context)

def gym_customer_profile(request, schema_name, customer_id):
    tenant = get_tenant(request, schema_name)
    from .models import GymCustomer, GymSubscription, GymPayment, GymAttendance
    from decimal import Decimal
    with schema_context(schema_name):
        customer = get_object_or_404(GymCustomer, id=customer_id)
        subscriptions = customer.subscriptions.all().order_by('-year', '-month')
        payments = customer.payments.all().order_by('-payment_date')
        attendances = customer.attendances.all().order_by('-date')
        total_fee = subscriptions.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        total_paid = payments.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        pending_total = total_fee - total_paid
        for a in attendances:
            a.can_edit = a.is_editable()
        context = {
            'tenant': tenant, 'customer': customer, 'subscriptions': subscriptions, 'payments': payments,
            'total_fee': total_fee, 'total_paid': total_paid, 'pending_total': pending_total,
            'attendances': attendances,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/gym_customer_profile.html', context)

# --------------------------------------------------------------
# FIXED GYM ATTENDANCE VIEW – uses timezone.localdate(), shows only eligible customers
# --------------------------------------------------------------
def gym_attendance(request, schema_name):
    tenant = get_tenant(request, schema_name)
    from .models import GymCustomer, GymAttendance, GymSubscription
    from datetime import timedelta
    from django.http import JsonResponse
    from django.views.decorators.csrf import csrf_exempt
    from django.utils import timezone

    if request.method == 'POST' and request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        # AJAX check-in
        customer_id = request.POST.get('customer_id')
        if not customer_id:
            return JsonResponse({'error': 'Customer ID required'}, status=400)
        with schema_context(schema_name):
            try:
                customer = GymCustomer.objects.get(id=customer_id)
            except GymCustomer.DoesNotExist:
                return JsonResponse({'error': 'Customer not found'}, status=404)
            today = timezone.localdate()
            # Check paid subscription for current month
            has_paid = customer.subscriptions.filter(month=today.month, year=today.year, status='paid').exists()
            if not has_paid:
                return JsonResponse({'error': f'No paid subscription for {today.strftime("%B %Y")}'}, status=403)
            # Check if already checked in today
            if GymAttendance.objects.filter(customer=customer, date=today).exists():
                return JsonResponse({'error': f'{customer.name} already checked in today.'}, status=400)
            # Create attendance record
            attendance = GymAttendance.objects.create(
                customer=customer, date=today, check_in=timezone.now()
            )
            return JsonResponse({
                'message': f'Check-in recorded for {customer.name}',
                'customer_name': customer.name,
                'customer_phone': customer.phone,
                'check_in_time': attendance.check_in.strftime('%H:%M'),
                'customer_id': customer.id,
                'attendance_id': attendance.id
            })
    elif request.method == 'POST' and not request.headers.get('X-Requested-With'):
        # Fallback to traditional POST (from old form) – redirect
        customer_id = request.POST.get('customer')
        if customer_id:
            with schema_context(schema_name):
                customer = get_object_or_404(GymCustomer, id=customer_id)
                today = timezone.localdate()
                has_paid = customer.subscriptions.filter(month=today.month, year=today.year, status='paid').exists()
                if not has_paid:
                    messages.error(request, f"Customer '{customer.name}' does not have a paid subscription for {today.strftime('%B %Y')}.")
                    return redirect('gym_attendance', schema_name=schema_name)
                if GymAttendance.objects.filter(customer=customer, date=today).exists():
                    messages.error(request, f"{customer.name} already checked in today.")
                    return redirect('gym_attendance', schema_name=schema_name)
                attendance = GymAttendance.objects.create(customer=customer, date=today, check_in=timezone.now())
                messages.success(request, f"Check-in recorded for {customer.name}")
                return redirect('gym_attendance', schema_name=schema_name)
        messages.error(request, "No customer selected")
        return redirect('gym_attendance', schema_name=schema_name)

    # GET request – render page
    with schema_context(schema_name):
        from django.utils import timezone
        today = timezone.localdate()
        print(f"[ATTENDANCE DEBUG] Today's date: {today}")

        # Attempt to get active check-ins using the date field
        active_checkins = GymAttendance.objects.filter(date=today, check_out__isnull=True).select_related('customer').order_by('-check_in')
        print(f"[ATTENDANCE DEBUG] Found {active_checkins.count()} active check-ins using date field")

        # If none found, try using check_in date and fix the date field
        if active_checkins.count() == 0:
            # Look for any check-ins without checkout that happened today (local date)
            for att in GymAttendance.objects.filter(check_out__isnull=True):
                att_local_date = timezone.localdate(att.check_in)
                if att_local_date == today:
                    print(f"[ATTENDANCE DEBUG] Found active attendance {att.id} with check_in {att.check_in} -> local date {att_local_date}")
                    # Fix its date field
                    att.date = att_local_date
                    att.save(update_fields=['date'])
                    # Re-query active check-ins
                    active_checkins = GymAttendance.objects.filter(date=today, check_out__isnull=True).select_related('customer')
                    break

        # Completed check-ins (checked in and checked out today)
        completed_today = GymAttendance.objects.filter(date=today, check_out__isnull=False).select_related('customer').order_by('-check_out')

        customers_with_paid = []
        for c in GymCustomer.objects.filter(status='active'):
            if c.subscriptions.filter(month=today.month, year=today.year, status='paid').exists():
                if not GymAttendance.objects.filter(customer=c, date=today).exists():
                    customers_with_paid.append(c)

        print(f"[ATTENDANCE DEBUG] Customers with paid subscription (not checked in today): {len(customers_with_paid)}")

        context = {
            'tenant': tenant,
            'customers_with_paid': customers_with_paid,
            'active_checkins': active_checkins,
            'completed_today': completed_today,
            'today': today,
            'total_active_customers': GymCustomer.objects.filter(status='active').count(),
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/gym_attendance.html', context)

def gym_payment(request, schema_name, customer_id=None):
    tenant = get_tenant(request, schema_name)
    from .models import GymCustomer, GymSubscription, GymPayment
    from .forms import GymPaymentForm
    from decimal import Decimal

    with schema_context(schema_name):
        if request.method == 'POST':
            customer_id = request.POST.get('customer_id')
            amount = request.POST.get('amount')
            mode = request.POST.get('payment_mode')
            remarks = request.POST.get('remarks', '')
            if customer_id and amount:
                customer = get_object_or_404(GymCustomer, id=customer_id)
                amount = Decimal(amount)
                pending_subs = customer.subscriptions.filter(status__in=['pending','partial','overdue']).order_by('due_date')
                total_pending = sum(s.remaining for s in pending_subs)
                if amount > total_pending:
                    messages.error(request, f"Amount exceeds total pending (₹{total_pending})")
                    return redirect('gym_payment', schema_name=schema_name, customer_id=customer.id)
                remaining = amount
                paid_subs = []
                for sub in pending_subs:
                    if remaining <= 0: break
                    due = sub.remaining
                    if remaining >= due:
                        sub.paid_amount = sub.amount
                        remaining -= due
                    else:
                        sub.paid_amount += remaining
                        remaining = 0
                    sub.save()
                    paid_subs.append(sub)
                payment = GymPayment.objects.create(
                    customer=customer, amount=amount, payment_mode=mode,
                    payment_type='full' if remaining==0 else 'partial', remarks=remarks,
                    created_by=request.session.get('school_admin_username', 'admin')
                )
                payment.subscriptions.set(paid_subs)
                messages.success(request, f"Payment of ₹{amount} received. Receipt: {payment.receipt_number}")
                return redirect('gym_payment', schema_name=schema_name, customer_id=customer.id)
            else:
                messages.error(request, "Invalid data")
                return redirect('gym_payment', schema_name=schema_name)

        customers_with_pending = []
        for c in GymCustomer.objects.filter(status='active'):
            pending = sum(s.remaining for s in c.subscriptions.filter(status__in=['pending','partial','overdue']))
            if pending > 0:
                c.pending_amount = pending
                customers_with_pending.append(c)
        customers_with_pending.sort(key=lambda x: x.pending_amount, reverse=True)

        selected_customer = None
        pending_subs = []
        total_pending = 0
        if customer_id:
            selected_customer = get_object_or_404(GymCustomer, id=customer_id)
            pending_subs = selected_customer.subscriptions.filter(status__in=['pending','partial','overdue']).order_by('due_date')
            total_pending = sum(s.remaining for s in pending_subs)

        recent_payments = list(GymPayment.objects.select_related('customer').order_by('-payment_date')[:5])
        context = {
            'tenant': tenant, 'customers': customers_with_pending, 'selected_customer': selected_customer,
            'pending_subs': pending_subs, 'total_pending': total_pending, 'recent_payments': recent_payments,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/gym_payment.html', context)

def gym_reports(request, schema_name):
    """Main reports page – loads initial context, then JS fetches data via APIs."""
    tenant = get_tenant(request, schema_name)
    from .models import GymCustomer, GymPayment, GymAttendance, GymSubscription
    with schema_context(schema_name):
        total_revenue_all = GymPayment.objects.aggregate(Sum('amount'))['amount__sum'] or 0
        total_checkins_all = GymAttendance.objects.count()
        active_customers = GymCustomer.objects.filter(status='active').count()
        total_customers = GymCustomer.objects.count()
        active_subs = GymSubscription.objects.filter(status='paid').count()
        expiring_soon = GymCustomer.objects.filter(
            status='active',
            membership_end__gte=timezone.localdate(),
            membership_end__lte=timezone.localdate() + timedelta(days=7)
        ).count()
        context = {
            'tenant': tenant,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
            'total_revenue_all': total_revenue_all,
            'total_checkins_all': total_checkins_all,
            'active_customers': active_customers,
            'total_customers': total_customers,
            'active_subs': active_subs,
            'expiring_soon': expiring_soon,
        }
    return render(request, 'tenant/gym_reports.html', context)

def gym_settings(request, schema_name):
    tenant = get_tenant(request, schema_name)
    from .models import GymSettings
    from .forms import GymSettingsForm
    with schema_context(schema_name):
        settings_obj, created = GymSettings.objects.get_or_create(pk=1)
        if request.method == 'POST':
            form = GymSettingsForm(request.POST, instance=settings_obj)
            if form.is_valid():
                form.save()
                messages.success(request, "Gym settings updated.")
                return redirect('gym_settings', schema_name=schema_name)
        else:
            form = GymSettingsForm(instance=settings_obj)
        context = {'tenant': tenant, 'form': form, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/gym_settings.html', context)

def gym_receipt(request, schema_name, receipt_id):
    tenant = get_tenant(request, schema_name)
    from .models import GymPayment
    with schema_context(schema_name):
        payment = get_object_or_404(GymPayment.objects.select_related('customer'), id=receipt_id)
        subscriptions = list(payment.subscriptions.all())
        context = {
            'tenant': tenant,
            'payment': payment,
            'subscriptions': subscriptions,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/gym_receipt.html', context)

# Subscription generation and cancellation
def gym_generate_subscription(request, schema_name, customer_id):
    from django.http import JsonResponse
    from .models import GymCustomer, GymSubscription, GymSettings
    from decimal import Decimal
    from datetime import date
    from calendar import monthrange
    import json

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    try:
        data = json.loads(request.body)
    except:
        data = request.POST
    months = int(data.get('months', 1))
    custom_fee = data.get('fee')
    if not custom_fee:
        return JsonResponse({'error': 'Fee amount required'}, status=400)
    custom_fee = Decimal(str(custom_fee))
    if months < 1 or months > 3:
        return JsonResponse({'error': 'Months must be between 1 and 3'}, status=400)

    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        customer = get_object_or_404(GymCustomer, id=customer_id)
        settings, _ = GymSettings.objects.get_or_create(pk=1)
        today = timezone.localdate()
        generated = []
        for i in range(months):
            gen_month = today.month + i
            gen_year = today.year
            while gen_month > 12:
                gen_month -= 12
                gen_year += 1
            existing = GymSubscription.objects.filter(customer=customer, month=gen_month, year=gen_year).first()
            if existing and existing.is_fully_paid:
                continue
            elif existing and not existing.is_fully_paid:
                existing.amount = custom_fee
                existing.due_date = date(gen_year, gen_month, min(settings.due_date_offset, monthrange(gen_year, gen_month)[1]))
                existing.is_cancelled = False
                existing.cancelled_on = None
                existing.save()
                generated.append(f"{gen_month}/{gen_year} (updated)")
            else:
                due_day = min(settings.due_date_offset, monthrange(gen_year, gen_month)[1])
                due_date = date(gen_year, gen_month, due_day)
                GymSubscription.objects.create(
                    customer=customer,
                    month=gen_month,
                    year=gen_year,
                    amount=custom_fee,
                    due_date=due_date,
                    status='pending'
                )
                generated.append(f"{gen_month}/{gen_year}")
        customer.monthly_fee = custom_fee
        customer.save()
        return JsonResponse({'message': f'Subscription generated for {len(generated)} month(s): {", ".join(generated)}'})

def gym_cancel_subscription(request, schema_name, subscription_id):
    from django.http import JsonResponse
    from .models import GymSubscription, GymPayment
    from decimal import Decimal
    from datetime import date
    from calendar import monthrange

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        sub = get_object_or_404(GymSubscription, id=subscription_id)
        if sub.is_cancelled:
            return JsonResponse({'error': 'Already cancelled'}, status=400)
        if sub.status == 'paid':
            return JsonResponse({'error': 'Fully paid subscriptions cannot be cancelled'}, status=400)

        today = timezone.localdate()
        days_in_month = monthrange(sub.year, sub.month)[1]
        if today.year == sub.year and today.month == sub.month:
            days_used = min(today.day, days_in_month)
        else:
            days_used = 0
        daily_rate = sub.amount / days_in_month
        used_amount = daily_rate * days_used
        refund = sub.paid_amount - used_amount
        if refund < 0:
            refund = Decimal('0.00')

        sub.is_cancelled = True
        sub.cancelled_on = today
        sub.paid_amount = used_amount
        sub.save()

        if refund > 0:
            GymPayment.objects.create(
                customer=sub.customer,
                amount=-refund,
                payment_mode='refund',
                payment_type='refund',
                remarks=f'Refund for cancelled subscription {sub.month}/{sub.year}',
                created_by=request.session.get('school_admin_username', 'admin')
            ).subscriptions.add(sub)

        return JsonResponse({'message': f'Subscription cancelled. Refund amount: ₹{refund}', 'refund': float(refund)})

def gym_edit_attendance(request, schema_name, attendance_id):
    from django.http import JsonResponse
    from .models import GymAttendance
    from .forms import AttendanceEditForm
    if request.method == 'GET':
        tenant = get_tenant(request, schema_name)
        with schema_context(schema_name):
            attendance = get_object_or_404(GymAttendance, id=attendance_id)
            data = {
                'check_in': attendance.check_in.isoformat() if attendance.check_in else '',
                'check_out': attendance.check_out.isoformat() if attendance.check_out else '',
                'notes': attendance.notes or '',
                'editable': True  # Always editable
            }
            return JsonResponse(data)
    elif request.method == 'POST':
        tenant = get_tenant(request, schema_name)
        with schema_context(schema_name):
            attendance = get_object_or_404(GymAttendance, id=attendance_id)
            form = AttendanceEditForm(request.POST, instance=attendance)
            if form.is_valid():
                form.save()
                return JsonResponse({'message': 'Attendance updated successfully'})
            else:
                return JsonResponse({'errors': form.errors}, status=400)

@csrf_exempt
@require_http_methods(["POST"])
def gym_checkin_api(request):
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({"error": "Unauthorized"}, status=401)
    schema_name = request.session.get('school_admin_schema')
    if not schema_name:
        return JsonResponse({"error": "No tenant schema"}, status=400)
    customer_id = request.POST.get('customer_id')
    if not customer_id:
        return JsonResponse({"error": "Customer ID required"}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({"error": "Tenant not found"}, status=404)
    with schema_context(schema_name):
        from .models import GymCustomer, GymAttendance, GymSubscription
        from datetime import date
        from django.utils import timezone
        customer = get_object_or_404(GymCustomer, id=customer_id)
        today = timezone.localdate()
        has_paid = customer.subscriptions.filter(month=today.month, year=today.year, status='paid').exists()
        if not has_paid:
            return JsonResponse({"error": "No active paid subscription for current month. Please renew subscription first."}, status=403)
        attendance, created = GymAttendance.objects.get_or_create(
            customer=customer, date=today,
            defaults={"check_in": timezone.now()}
        )
        return JsonResponse({
            "message": f"Check-in recorded for {customer.name}",
            "customer_name": customer.name,
            "customer_phone": customer.phone,
            "check_in_time": attendance.check_in.strftime('%H:%M'),
            "customer_id": customer.id,
            "already_checked_in": not created
        })

@csrf_exempt
@require_http_methods(["POST"])
def gym_checkout_api(request):
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({"error": "Unauthorized"}, status=401)
    schema_name = request.session.get('school_admin_schema')
    if not schema_name:
        return JsonResponse({"error": "No tenant schema"}, status=400)
    customer_id = request.POST.get('customer_id')
    if not customer_id:
        return JsonResponse({"error": "Customer ID required"}, status=400)
    try:
        tenant = SchoolClient.objects.get(schema_name=schema_name)
    except SchoolClient.DoesNotExist:
        return JsonResponse({"error": "Tenant not found"}, status=404)
    with schema_context(schema_name):
        from .models import GymCustomer, GymAttendance, GymSubscription
        from datetime import date
        customer = get_object_or_404(GymCustomer, id=customer_id)
        today = timezone.localdate()
        has_paid = customer.subscriptions.filter(month=today.month, year=today.year, status='paid').exists()
        if not has_paid:
            return JsonResponse({"error": "No active paid subscription for current month. Please renew subscription first."}, status=403)
        attendance = GymAttendance.objects.filter(customer=customer, date=today).first()
        if not attendance:
            return JsonResponse({"error": "No check-in found for today"}, status=400)
        if attendance.check_out:
            return JsonResponse({"error": "Already checked out"}, status=400)
        attendance.check_out = timezone.now()
        attendance.save()
        return JsonResponse({
            "message": f"Check-out recorded for {customer.name}",
            "customer_name": customer.name,
            "customer_phone": customer.phone,
            "attendance_id": attendance.id
        })

def gym_reports(request, schema_name):
    """Main reports page – loads initial context, then JS fetches data via APIs."""
    tenant = get_tenant(request, schema_name)
    from .models import GymCustomer, GymPayment, GymAttendance, GymSubscription
    with schema_context(schema_name):
        # Initial KPI totals (all time)
        total_revenue_all = GymPayment.objects.aggregate(Sum('amount'))['amount__sum'] or 0
        total_checkins_all = GymAttendance.objects.count()
        active_customers = GymCustomer.objects.filter(status='active').count()
        total_customers = GymCustomer.objects.count()
        # Active subscriptions count
        active_subs = GymSubscription.objects.filter(status='paid').count()
        expiring_soon = GymCustomer.objects.filter(
            status='active',
            membership_end__gte=timezone.localdate(),
            membership_end__lte=timezone.localdate() + timedelta(days=7)
        ).count()
        context = {
            'tenant': tenant,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
            'total_revenue_all': total_revenue_all,
            'total_checkins_all': total_checkins_all,
            'active_customers': active_customers,
            'total_customers': total_customers,
            'active_subs': active_subs,
            'expiring_soon': expiring_soon,
        }
    return render(request, 'tenant/gym_reports.html', context)

@csrf_exempt
def gym_revenue_stats_api(request, schema_name):
    """API: revenue stats for given date range and grouping (day/month)."""
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    tenant = get_tenant(request, schema_name)
    start_str = request.GET.get('start')
    end_str = request.GET.get('end')
    group_by = request.GET.get('group_by', 'month')  # day or month
    try:
        start_date = datetime.strptime(start_str, '%Y-%m-%d').date() if start_str else None
        end_date = datetime.strptime(end_str, '%Y-%m-%d').date() if end_str else None
    except:
        return JsonResponse({'error': 'Invalid date format'}, status=400)
    
    with schema_context(schema_name):
        from .models import GymPayment
        qs = GymPayment.objects.all()
        if start_date:
            qs = qs.filter(payment_date__gte=start_date)
        if end_date:
            qs = qs.filter(payment_date__lte=end_date)
        
        if group_by == 'day':
            data = qs.annotate(day=TruncDay('payment_date')).values('day').annotate(total=Sum('amount')).order_by('day')
            labels = [d['day'].strftime('%Y-%m-%d') for d in data]
            amounts = [float(d['total']) for d in data]
        else:
            data = qs.annotate(month=TruncMonth('payment_date')).values('month').annotate(total=Sum('amount')).order_by('month')
            labels = [d['month'].strftime('%b %Y') for d in data]
            amounts = [float(d['total']) for d in data]
        
        # Payment mode distribution
        mode_totals = {}
        for mode_code, mode_name in GymPayment.PAYMENT_MODE_CHOICES:
            total = qs.filter(payment_mode=mode_code).aggregate(Sum('amount'))['amount__sum'] or 0
            if total > 0:
                mode_totals[mode_name] = float(total)
        mode_distribution = [{'name': k, 'amount': v} for k, v in mode_totals.items()]
        
        # Top spenders (customers with highest total payments in range)
        top_spenders = qs.values('customer__id', 'customer__name', 'customer__phone').annotate(total=Sum('amount')).order_by('-total')[:5]
        top_spenders_list = [{'id': c['customer__id'], 'name': c['customer__name'], 'phone': c['customer__phone'], 'total': float(c['total'])} for c in top_spenders]
        
        return JsonResponse({
            'labels': labels,
            'amounts': amounts,
            'mode_distribution': mode_distribution,
            'top_spenders': top_spenders_list,
            'total_revenue': float(qs.aggregate(Sum('amount'))['amount__sum'] or 0),
            'transaction_count': qs.count()
        })

@csrf_exempt
def gym_attendance_stats_api(request, schema_name):
    """API: attendance stats for date range."""
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    tenant = get_tenant(request, schema_name)
    start_str = request.GET.get('start')
    end_str = request.GET.get('end')
    try:
        start_date = datetime.strptime(start_str, '%Y-%m-%d').date() if start_str else None
        end_date = datetime.strptime(end_str, '%Y-%m-%d').date() if end_str else None
    except:
        return JsonResponse({'error': 'Invalid date format'}, status=400)
    
    with schema_context(schema_name):
        from .models import GymAttendance
        qs = GymAttendance.objects.all()
        if start_date:
            qs = qs.filter(date__gte=start_date)
        if end_date:
            qs = qs.filter(date__lte=end_date)
        
        # Daily check-ins
        daily = qs.values('date').annotate(count=Count('id')).order_by('date')
        labels = [d['date'].strftime('%Y-%m-%d') for d in daily]
        counts = [d['count'] for d in daily]
        
        # Check-in hour distribution
        hour_dist = defaultdict(int)
        for att in qs:
            hour_dist[att.check_in.hour] += 1
        hours = sorted(hour_dist.keys())
        hour_counts = [hour_dist[h] for h in hours]
        
        # Unique customers
        unique_customers = qs.values('customer').distinct().count()
        
        # Average per day
        if daily:
            avg_per_day = sum(counts) / len(daily)
        else:
            avg_per_day = 0
        
        return JsonResponse({
            'labels': labels,
            'counts': counts,
            'hour_labels': hours,
            'hour_counts': hour_counts,
            'total_checkins': qs.count(),
            'unique_customers': unique_customers,
            'avg_per_day': round(avg_per_day, 1)
        })

@csrf_exempt
def gym_customers_list_api(request, schema_name):
    """API: list of all customers with basic stats (total paid, pending, attendance count)."""
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    tenant = get_tenant(request, schema_name)
    search = request.GET.get('search', '')
    status_filter = request.GET.get('status', '')
    
    with schema_context(schema_name):
        from .models import GymCustomer, GymPayment, GymSubscription, GymAttendance
        customers = GymCustomer.objects.all()
        if search:
            customers = customers.filter(Q(name__icontains=search) | Q(phone__icontains=search))
        if status_filter:
            customers = customers.filter(status=status_filter)
        
        data = []
        for c in customers:
            total_paid = c.payments.aggregate(Sum('amount'))['amount__sum'] or 0
            pending = sum(s.remaining for s in c.subscriptions.filter(status__in=['pending','partial','overdue']))
            attendance_count = c.attendances.count()
            data.append({
                'id': c.id,
                'name': c.name,
                'phone': c.phone,
                'status': c.status,
                'membership_end': c.membership_end.strftime('%Y-%m-%d') if c.membership_end else None,
                'total_paid': float(total_paid),
                'pending': float(pending),
                'attendance_count': attendance_count
            })
        return JsonResponse(data, safe=False)

@csrf_exempt
def gym_customer_detail_api(request, schema_name, customer_id):
    """API: detailed info for a single customer (payments, subscriptions, attendance)."""
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        from .models import GymCustomer, GymPayment, GymSubscription, GymAttendance
        customer = get_object_or_404(GymCustomer, id=customer_id)
        # Payments
        payments = customer.payments.all().order_by('-payment_date')
        payments_data = [{
            'receipt': p.receipt_number,
            'amount': float(p.amount),
            'date': p.payment_date.strftime('%Y-%m-%d'),
            'mode': p.get_payment_mode_display()
        } for p in payments]
        # Subscriptions
        subs = customer.subscriptions.all().order_by('-year', '-month')
        subs_data = [{
            'month': f"{s.month}/{s.year}",
            'amount': float(s.amount),
            'paid': float(s.paid_amount),
            'status': s.get_status_display(),
            'cancelled': s.is_cancelled
        } for s in subs]
        # Attendance
        attendances = customer.attendances.all().order_by('-date')
        attendance_data = [{
            'date': a.date.strftime('%Y-%m-%d'),
            'check_in': a.check_in.strftime('%H:%M'),
            'check_out': a.check_out.strftime('%H:%M') if a.check_out else None
        } for a in attendances]
        
        total_paid = sum(p.amount for p in payments)
        pending = sum(s.remaining for s in subs if s.status in ['pending','partial','overdue'])
        
        return JsonResponse({
            'id': customer.id,
            'name': customer.name,
            'phone': customer.phone,
            'email': customer.email,
            'status': customer.status,
            'membership_start': customer.membership_start.strftime('%Y-%m-%d'),
            'membership_end': customer.membership_end.strftime('%Y-%m-%d') if customer.membership_end else None,
            'monthly_fee': float(customer.monthly_fee),
            'total_paid': float(total_paid),
            'pending': float(pending),
            'payments': payments_data,
            'subscriptions': subs_data,
            'attendances': attendance_data
        })

@csrf_exempt
def gym_subscription_status_api(request, schema_name):
    """API: subscription status summary and list."""
    if not request.session.get('school_admin_authenticated'):
        return JsonResponse({'error': 'Unauthorized'}, status=401)
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        from .models import GymSubscription, GymCustomer
        today = timezone.localdate()
        # Active subscriptions (paid for current month)
        active_subs = GymSubscription.objects.filter(
            month=today.month, year=today.year, status='paid'
        ).select_related('customer')
        # Expiring soon (customers whose membership ends within 7 days)
        expiring_customers = GymCustomer.objects.filter(
            status='active',
            membership_end__gte=today,
            membership_end__lte=today + timedelta(days=7)
        )
        # Expired customers
        expired_customers = GymCustomer.objects.filter(status='expired')
        
        active_list = [{'customer': sub.customer.name, 'amount': float(sub.amount)} for sub in active_subs]
        expiring_list = [{'name': c.name, 'phone': c.phone, 'end_date': c.membership_end.strftime('%Y-%m-%d')} for c in expiring_customers]
        expired_list = [{'name': c.name, 'phone': c.phone, 'end_date': c.membership_end.strftime('%Y-%m-%d') if c.membership_end else ''} for c in expired_customers]
        
        return JsonResponse({
            'active_count': active_subs.count(),
            'expiring_count': expiring_customers.count(),
            'expired_count': expired_customers.count(),
            'active_subscriptions': active_list,
            'expiring_soon': expiring_list,
            'expired_customers': expired_list
        })
