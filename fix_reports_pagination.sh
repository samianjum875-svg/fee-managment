#!/bin/bash

# fix_reports_pagination.sh - Fixes reports page: data display, pagination, filters
# Run from: ~/axis_school_sys

set -e

VIEWS_FILE="axis_saas/views.py"
TEMPLATE_FILE="templates/tenant/reports.html"

if [ ! -f "$VIEWS_FILE" ] || [ ! -f "$TEMPLATE_FILE" ]; then
    echo "ERROR: Required files not found. Are you in the project root?"
    exit 1
fi

# Backup
cp "$VIEWS_FILE" "${VIEWS_FILE}.bak_reports"
cp "$TEMPLATE_FILE" "${TEMPLATE_FILE}.bak_reports"
echo "✅ Backups created."

# ----------------------------------------------------------------------
# 1. Replace the reports view with paginated version
# ----------------------------------------------------------------------
echo "✍️  Updating reports view with pagination..."

python3 << 'PYTHON_SCRIPT'
import re

view_file = "axis_saas/views.py"

with open(view_file, "r") as f:
    content = f.read()

# Find the reports function (starts with "def reports(")
pattern = r'^def reports\(request, schema_name\):.*?(?=^def [a-zA-Z_]|$)'
match = re.search(pattern, content, re.DOTALL | re.MULTILINE)
if not match:
    print("❌ Could not find reports function. Exiting.")
    exit(1)

new_func = '''def reports(request, schema_name):
    tenant = get_tenant(request, schema_name)
    report_type = request.GET.get('type', 'collection')
    today = date.today()
    quick_filter = request.GET.get('quick_filter')
    start_date_str = request.GET.get('start_date')
    end_date_str = request.GET.get('end_date')
    search_q = request.GET.get('search', '').strip()
    page_num = request.GET.get('page', 1)
    
    with schema_context(schema_name):
        total_payments_all = PaymentTransaction.objects.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
    
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
        # Default: if any payments exist, show all time; else last 6 months
        if total_payments_all > 0:
            start_date = date(2000, 1, 1)
            end_date = today
            quick_filter = 'all'
        else:
            start_date = today - timedelta(days=180)
            end_date = today
            quick_filter = 'last6months'
    
    with schema_context(schema_name):
        payments_qs = PaymentTransaction.objects.filter(payment_date__gte=start_date, payment_date__lte=end_date)
        if search_q:
            payments_qs = payments_qs.filter(
                Q(receipt_number__icontains=search_q) |
                Q(student__name__icontains=search_q) |
                Q(student__roll_number__icontains=search_q)
            )
        
        # Pagination
        paginator = Paginator(payments_qs.order_by('-payment_date'), 15)
        payments_page = paginator.get_page(page_num)
        
        total_collection = payments_qs.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        payment_count = payments_qs.count()
        
        # Pending fees (all time, not filtered by date)
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
            'payments': payments_page,          # paginated
            'total': total_collection,
            'payment_count': payment_count,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
            'total_collection_all': total_collection_all,
        }
    return render(request, 'tenant/reports.html', context)
'''

# Replace the function
new_content = content[:match.start()] + new_func + content[match.end():]
with open(view_file, "w") as f:
    f.write(new_content)

print("✅ reports view updated with pagination.")
PYTHON_SCRIPT

# ----------------------------------------------------------------------
# 2. Update the template: add pagination controls
# ----------------------------------------------------------------------
echo "✍️  Updating reports.html with pagination controls..."

# We'll replace the entire Transaction History table section with a paginated version
# Using a heredoc to insert the new block. Since the template is large, we'll locate and replace the relevant part.

python3 << 'PYTHON_SCRIPT'
import re

template_file = "templates/tenant/reports.html"

with open(template_file, "r") as f:
    content = f.read()

# Find the {% if report_type == 'collection' %} block
pattern = r'({% if report_type == \'collection\' %}.*?{% else %}.*?{% endif %})'
# We'll replace the entire block from that tag to the matching {% else %} (but careful)
# Simpler: replace the whole collection block with a new version that includes pagination.

# Locate the start and end of the collection block
start_tag = "{% if report_type == 'collection' %}"
end_tag = "{% else %}"
start_idx = content.find(start_tag)
if start_idx == -1:
    print("❌ Could not find the collection block start.")
    exit(1)

end_idx = content.find(end_tag, start_idx)
if end_idx == -1:
    print("❌ Could not find the else tag.")
    exit(1)

# Extract the part before and after
before = content[:start_idx]
after = content[end_idx:]

new_collection_block = '''{% if report_type == 'collection' %}
<div class="table-card">
    <div class="table-header">
        <h3>Transaction History</h3>
        <div class="table-total">Total: ₹{{ total|floatformat:2 }} ({{ payment_count }} transactions)</div>
    </div>
    <div class="table-search-bar">
        <form method="get" class="search-form-inline">
            <input type="hidden" name="type" value="collection">
            <input type="hidden" name="start_date" value="{{ start_date|date:'Y-m-d' }}">
            <input type="hidden" name="end_date" value="{{ end_date|date:'Y-m-d' }}">
            <input type="hidden" name="quick_filter" value="{{ quick_filter }}">
            <input type="text" name="search" placeholder="Search by Receipt No, Student Name or Roll Number" value="{{ search_query }}" class="search-input-wide">
            <button type="submit" class="btn-filter">🔍 Search</button>
            {% if search_query %}<a href="?type=collection&start_date={{ start_date|date:'Y-m-d' }}&end_date={{ end_date|date:'Y-m-d' }}{% if quick_filter %}&quick_filter={{ quick_filter }}{% endif %}" class="btn-reset">Clear</a>{% endif %}
        </form>
    </div>
    <div class="table-responsive">
        <table class="data-table">
            <thead>
                <tr><th>Receipt No</th><th>Student</th><th>Amount</th><th>Date</th><th>Mode</th><th>Receipt</th></tr>
            </thead>
            <tbody>
                {% for p in payments %}
                <tr>
                    <td><code>{{ p.receipt_number }}</code></td>
                    <td><strong>{{ p.student.name }}</strong><br><small>{{ p.student.roll_number }} | {{ p.student.grade }} - {{ p.student.section }}</small></td>
                    <td class="amount">₹{{ p.amount|floatformat:2 }}</td>
                    <td>{{ p.payment_date|date:"d M Y" }}</td>
                    <td>{{ p.get_payment_mode_display }}</td>
                    <td><a href="{% url 'fee_receipt' schema_name=tenant.schema_name receipt_id=p.id %}" class="receipt-link" target="_blank">View</a></td>
                </tr>
                {% empty %}
                <tr><td colspan="6" class="empty-row">
                    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M8 12h8"/></svg>
                    <p>No payments in the selected date range.</p>
                    {% if total_collection_all > 0 %}
                    <p class="mt-2">There are <strong>₹{{ total_collection_all|floatformat:2 }}</strong> total payments recorded. Try expanding the date range using the filters above, or click <a href="?type=collection&quick_filter=all">All Time</a>.</p>
                    {% else %}
                    <p>No payments have been recorded yet. Go to <a href="{% url 'fee_collection' schema_name=tenant.schema_name %}">Fee Collection</a> to collect fees.</p>
                    {% endif %}
                </td></tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
    {% if payments.has_other_pages %}
    <div class="pagination" style="margin-top: 1rem; text-align: center;">
        {% if payments.has_previous %}
            <a href="?type=collection&page={{ payments.previous_page_number }}{% if start_date %}&start_date={{ start_date|date:'Y-m-d' }}{% endif %}{% if end_date %}&end_date={{ end_date|date:'Y-m-d' }}{% endif %}{% if quick_filter %}&quick_filter={{ quick_filter }}{% endif %}{% if search_query %}&search={{ search_query }}{% endif %}" class="page-link">Previous</a>
        {% endif %}
        <span class="current-page">Page {{ payments.number }} of {{ payments.paginator.num_pages }}</span>
        {% if payments.has_next %}
            <a href="?type=collection&page={{ payments.next_page_number }}{% if start_date %}&start_date={{ start_date|date:'Y-m-d' }}{% endif %}{% if end_date %}&end_date={{ end_date|date:'Y-m-d' }}{% endif %}{% if quick_filter %}&quick_filter={{ quick_filter }}{% endif %}{% if search_query %}&search={{ search_query }}{% endif %}" class="page-link">Next</a>
        {% endif %}
    </div>
    {% endif %}
</div>
{% else %}'''

# Replace the block
new_content = before + new_collection_block + after
with open(template_file, "w") as f:
    f.write(new_content)

print("✅ reports.html updated with pagination controls.")
PYTHON_SCRIPT

echo ""
echo "🎉 Fix complete! Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
echo ""
echo "Now the reports page will show transaction history with pagination (15 per page)."
echo "Filters (date range, search) will work and keep pagination state."
