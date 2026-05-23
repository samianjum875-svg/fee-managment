#!/bin/bash

# fix_reports_simple.sh - Replaces reports view with a clean, working version
# Run from: ~/axis_school_sys

set -e

VIEWS_FILE="axis_saas/views.py"

if [ ! -f "$VIEWS_FILE" ]; then
    echo "ERROR: $VIEWS_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup
cp "$VIEWS_FILE" "${VIEWS_FILE}.bak_simple"
echo "✅ Backup created."

# Replace the reports function with a simplified, correct version
echo "✍️  Replacing reports function..."

python3 << 'PYTHON_SCRIPT'
import re

view_file = "axis_saas/views.py"

with open(view_file, "r") as f:
    content = f.read()

# Find the start of the reports function (first occurrence)
pattern = r'^def reports\(request, schema_name\):'
match = re.search(pattern, content, re.MULTILINE)
if not match:
    print("❌ Could not find reports function. Exiting.")
    exit(1)

start_pos = match.start()

# Find the next top-level function (to know where this function ends)
next_func_pattern = r'^\ndef [a-zA-Z_]\w*\('
next_match = re.search(next_func_pattern, content[start_pos+1:], re.MULTILINE)
if next_match:
    end_pos = start_pos + 1 + next_match.start()
else:
    end_pos = len(content)

# New clean reports function
new_func = '''def reports(request, schema_name):
    tenant = get_tenant(request, schema_name)
    report_type = request.GET.get('type', 'collection')
    today = date.today()
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
        # Default: show all time
        start_date = date(2000, 1, 1)
        end_date = today
        quick_filter = 'all'

    with schema_context(schema_name):
        # Base queryset for payments (filter by date range)
        payments_qs = PaymentTransaction.objects.filter(payment_date__gte=start_date, payment_date__lte=end_date)
        if search_q:
            payments_qs = payments_qs.filter(
                Q(receipt_number__icontains=search_q) |
                Q(student__name__icontains=search_q) |
                Q(student__roll_number__icontains=search_q)
            )

        # Paginate (15 per page)
        paginator = Paginator(payments_qs.order_by('-payment_date'), 15)
        payments_page = paginator.get_page(page_num)

        total_collection = payments_qs.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        payment_count = payments_qs.count()

        # Pending fees (all time)
        pending_records = FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue'])
        total_pending = sum(r.remaining for r in pending_records)

        total_collection_all = PaymentTransaction.objects.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        total_billed = total_collection_all + total_pending
        collection_rate = (float(total_collection_all) / float(total_billed) * 100) if total_billed > 0 else 0

        defaulters_count = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct().count()

        # Monthly trend (last 6 months)
        monthly_data = []
        for i in range(5, -1, -1):
            m = today.month - i
            y = today.year
            if m <= 0:
                m += 12
                y -= 1
            total = PaymentTransaction.objects.filter(payment_date__year=y, payment_date__month=m).aggregate(Sum('amount'))['amount__sum'] or 0
            monthly_data.append({'month': f"{m}/{y}", 'amount': float(total)})

        # Payment mode distribution (filtered by date range)
        mode_totals = {}
        for mode_code, mode_name in PaymentTransaction.PAYMENT_MODE_CHOICES:
            total = payments_qs.filter(payment_mode=mode_code).aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
            if total > 0:
                mode_totals[mode_name] = float(total)
        mode_distribution = [{'name': k, 'amount': v} for k, v in mode_totals.items()]

        # Class-wise pending fees
        class_pending = []
        grades = Student.objects.values_list('grade', flat=True).distinct().order_by('grade')
        grades = list(grades)
        for grade in grades:
            students = Student.objects.filter(grade=grade)
            pending = sum(sum(fr.remaining for fr in s.fee_records.filter(status__in=['pending', 'partial', 'overdue'])) for s in students)
            if pending > 0:
                class_pending.append({'grade': grade, 'pending': float(pending)})
        class_pending.sort(key=lambda x: x['pending'], reverse=True)

        # Top defaulters (max 5)
        top_defaulters = []
        for student in Student.objects.all():
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            if pending > 0:
                top_defaulters.append({'student': student, 'pending': float(pending)})
        top_defaulters = sorted(top_defaulters, key=lambda x: x['pending'], reverse=True)[:5]

        # Detailed defaulters list for the 'defaulters' tab
        defaulters_list = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct()
        defaulters_data = []
        for student in defaulters_list:
            pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending', 'partial', 'overdue']))
            oldest_due = student.fee_records.filter(status__in=['pending', 'partial', 'overdue']).order_by('due_date').first()
            days_overdue = (date.today() - oldest_due.due_date).days if oldest_due and oldest_due.due_date < date.today() else 0
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
            'payments': payments_page,          # paginated object
            'total': total_collection,
            'payment_count': payment_count,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
            'total_collection_all': total_collection_all,
        }
    return render(request, 'tenant/reports.html', context)
'''

# Replace the function
new_content = content[:start_pos] + new_func + content[end_pos:]

# Remove any duplicate reports functions (in case there are still two)
lines = new_content.splitlines(keepends=True)
new_lines = []
in_reports = False
reports_count = 0
for line in lines:
    if line.strip().startswith("def reports("):
        reports_count += 1
        if reports_count > 1:
            in_reports = True
            continue
    if in_reports and line.strip().startswith("def "):
        in_reports = False
    if not in_reports:
        new_lines.append(line)
new_content = "".join(new_lines)

with open(view_file, "w") as f:
    f.write(new_content)

print("✅ reports function replaced successfully.")
PYTHON_SCRIPT

echo ""
echo "🎉 Fix complete! Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
echo ""
echo "Now the reports page will show all payment transactions (paginated) and filters will work correctly."
