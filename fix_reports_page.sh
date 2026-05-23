#!/bin/bash

# fix_reports_page.sh - Overhauls the reports page (template + view)
# Run from project root: ~/axis_school_sys

set -e

TEMPLATE_FILE="templates/tenant/reports.html"
VIEWS_FILE="axis_saas/views.py"

echo "=== AXIS Reports Page Fix ==="

# 1. Backup original files (optional)
if [ ! -f "${TEMPLATE_FILE}.bak" ]; then
    cp "$TEMPLATE_FILE" "${TEMPLATE_FILE}.bak"
    echo "✅ Backup of $TEMPLATE_FILE saved as ${TEMPLATE_FILE}.bak"
fi
if [ ! -f "${VIEWS_FILE}.bak" ]; then
    cp "$VIEWS_FILE" "${VIEWS_FILE}.bak"
    echo "✅ Backup of $VIEWS_FILE saved as ${VIEWS_FILE}.bak"
fi

# 2. Write new reports.html (completely redesigned)
echo "✍️  Writing new $TEMPLATE_FILE ..."

cat > "$TEMPLATE_FILE" << 'EOF'
{% extends 'tenant/base.html' %}
{% load fee_extras %}
{% block title %}Financial Reports | {{ tenant.name }}{% endblock %}
{% block extra_head %}
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
/* additional fine-tuning */
.filter-card .filter-row {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
    align-items: flex-end;
    justify-content: space-between;
}
.quick-filters {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: center;
}
.quick-filter-btn {
    padding: 0.3rem 0.9rem;
    border-radius: 2rem;
    background: var(--surface-alt);
    border: 1px solid var(--border);
    text-decoration: none;
    color: var(--text);
    font-size: 0.8rem;
    transition: all 0.2s;
}
.quick-filter-btn.active, .quick-filter-btn:hover {
    background: var(--primary);
    color: white;
    border-color: var(--primary);
}
.custom-date-form {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: flex-end;
}
.date-group {
    display: flex;
    flex-direction: column;
}
.date-group label {
    font-size: 0.7rem;
    color: var(--muted);
}
.filter-input {
    padding: 0.4rem 0.6rem;
    border-radius: 0.5rem;
    border: 1px solid var(--border);
    background: var(--surface-alt);
    color: var(--text);
}
.btn-filter, .btn-reset {
    padding: 0.4rem 1rem;
    border-radius: 2rem;
    font-weight: 500;
    cursor: pointer;
    border: none;
}
.btn-filter {
    background: var(--primary);
    color: white;
}
.btn-reset {
    background: var(--surface-alt);
    color: var(--text);
    border: 1px solid var(--border);
}
.kpi-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 1rem;
    margin-bottom: 1.5rem;
}
.kpi-card {
    background: var(--surface);
    border-radius: var(--radius);
    border: 1px solid var(--border);
    padding: 1rem;
    display: flex;
    align-items: center;
    gap: 1rem;
    transition: transform 0.2s;
}
.kpi-card:hover {
    transform: translateY(-3px);
}
.kpi-icon {
    width: 48px;
    height: 48px;
    background: var(--surface-alt);
    border-radius: 2rem;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--primary);
}
.kpi-content {
    flex: 1;
}
.kpi-label {
    font-size: 0.7rem;
    text-transform: uppercase;
    color: var(--muted);
    letter-spacing: 0.5px;
}
.kpi-value {
    font-size: 1.5rem;
    font-weight: 700;
    line-height: 1.2;
}
.kpi-period {
    font-size: 0.7rem;
    color: var(--muted);
}
.charts-row {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
    gap: 1.5rem;
    margin-bottom: 1.5rem;
}
.chart-card {
    background: var(--surface);
    border-radius: var(--radius);
    border: 1px solid var(--border);
    padding: 1rem;
}
.chart-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 1rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.5rem;
}
.chart-header svg {
    color: var(--primary);
}
.chart-header h3 {
    font-size: 1rem;
    font-weight: 600;
    margin: 0;
}
.tabs {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1.5rem;
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.5rem;
}
.tab {
    padding: 0.4rem 1.2rem;
    border-radius: 2rem;
    text-decoration: none;
    color: var(--muted);
    font-weight: 500;
    transition: all 0.2s;
}
.tab.active {
    background: var(--primary);
    color: white;
}
.tab:hover:not(.active) {
    background: var(--surface-alt);
    color: var(--text);
}
.table-card {
    background: var(--surface);
    border-radius: var(--radius);
    border: 1px solid var(--border);
    overflow: hidden;
}
.table-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    background: var(--surface-alt);
    border-bottom: 1px solid var(--border);
}
.table-total {
    font-size: 0.85rem;
    background: var(--primary);
    color: white;
    padding: 0.2rem 0.8rem;
    border-radius: 2rem;
}
.table-search-bar {
    padding: 0.75rem 1rem;
    background: var(--surface-alt);
    border-bottom: 1px solid var(--border);
}
.search-form-inline {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
}
.search-input-wide {
    flex: 1;
    padding: 0.5rem 1rem;
    border-radius: 2rem;
    border: 1px solid var(--border);
    background: var(--surface-alt);
}
.table-responsive {
    overflow-x: auto;
}
.data-table {
    width: 100%;
    border-collapse: collapse;
}
.data-table th, .data-table td {
    padding: 0.75rem 1rem;
    text-align: left;
    border-bottom: 1px solid var(--border);
}
.data-table th {
    background: var(--surface-alt);
    font-weight: 600;
    font-size: 0.75rem;
    text-transform: uppercase;
    color: var(--muted);
}
.amount {
    font-weight: 600;
    color: var(--primary);
}
.pending {
    color: var(--danger);
    font-weight: 600;
}
.receipt-link {
    color: var(--primary);
    text-decoration: none;
}
.empty-row {
    text-align: center;
    padding: 2rem;
    color: var(--muted);
}
.overdue-badge {
    display: inline-block;
    padding: 0.2rem 0.6rem;
    border-radius: 2rem;
    font-size: 0.7rem;
    font-weight: 600;
}
.overdue-badge.medium { background: #fed7aa; color: #9a3412; }
.overdue-badge.high { background: #fee2e2; color: #991b1b; }
.overdue-badge.critical { background: #fecaca; color: #7f1d1d; }
[data-theme="dark"] .overdue-badge.medium { background: #7c2d12; color: #fdba74; }
[data-theme="dark"] .overdue-badge.high { background: #7f1d1d; color: #fecaca; }
[data-theme="dark"] .overdue-badge.critical { background: #991b1b; color: #fecaca; }
.top-defaulters-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}
.defaulter-item {
    display: flex;
    justify-content: space-between;
    padding: 0.5rem;
    background: var(--surface-alt);
    border-radius: 0.5rem;
}
</style>
{% endblock %}

{% block body %}
<div class="page-header">
    <div>
        <h1 class="page-title">Financial Reports</h1>
        <p class="page-desc">Complete analytics and transaction history</p>
    </div>
</div>

<!-- Advanced Filters -->
<div class="filter-card">
    <div class="filter-row">
        <div class="quick-filters">
            <span class="filter-label">Quick Range:</span>
            <a href="?type={{ report_type }}&quick_filter=today" class="quick-filter-btn {% if quick_filter == 'today' %}active{% endif %}">Today</a>
            <a href="?type={{ report_type }}&quick_filter=week" class="quick-filter-btn {% if quick_filter == 'week' %}active{% endif %}">This Week</a>
            <a href="?type={{ report_type }}&quick_filter=month" class="quick-filter-btn {% if quick_filter == 'month' %}active{% endif %}">This Month</a>
            <a href="?type={{ report_type }}&quick_filter=year" class="quick-filter-btn {% if quick_filter == 'year' %}active{% endif %}">This Year</a>
            <a href="?type={{ report_type }}&quick_filter=all" class="quick-filter-btn {% if quick_filter == 'all' %}active{% endif %}">All Time</a>
            <a href="?type={{ report_type }}&quick_filter=last6months" class="quick-filter-btn {% if quick_filter == 'last6months' %}active{% endif %}">Last 6 Months</a>
        </div>
        <form method="get" class="custom-date-form">
            <input type="hidden" name="type" value="{{ report_type }}">
            <div class="date-group">
                <label>From:</label>
                <input type="date" name="start_date" value="{{ start_date|date:'Y-m-d' }}" class="filter-input">
            </div>
            <div class="date-group">
                <label>To:</label>
                <input type="date" name="end_date" value="{{ end_date|date:'Y-m-d' }}" class="filter-input">
            </div>
            <button type="submit" class="btn-filter">Apply</button>
            <a href="?type={{ report_type }}" class="btn-reset">Reset</a>
        </form>
    </div>
</div>

<!-- KPI Cards -->
<div class="kpi-grid">
    <div class="kpi-card">
        <div class="kpi-icon"><svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg></div>
        <div class="kpi-content">
            <span class="kpi-label">Total Collection</span>
            <span class="kpi-value">₹{{ total_collection|floatformat:2 }}</span>
            <span class="kpi-period">{{ start_date|date:"d M Y" }} - {{ end_date|date:"d M Y" }}</span>
        </div>
    </div>
    <div class="kpi-card">
        <div class="kpi-icon"><svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M3 12h3l3-9 3 18 3-9h3"/></svg></div>
        <div class="kpi-content">
            <span class="kpi-label">Total Pending</span>
            <span class="kpi-value">₹{{ total_pending|floatformat:2 }}</span>
            <span class="kpi-period">All time</span>
        </div>
    </div>
    <div class="kpi-card">
        <div class="kpi-icon"><svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/><path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg></div>
        <div class="kpi-content">
            <span class="kpi-label">Collection Rate</span>
            <span class="kpi-value">{{ collection_rate }}%</span>
            <span class="kpi-period">Overall</span>
        </div>
    </div>
    <div class="kpi-card">
        <div class="kpi-icon"><svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/></svg></div>
        <div class="kpi-content">
            <span class="kpi-label">Active Defaulters</span>
            <span class="kpi-value">{{ defaulters_count }}</span>
            <span class="kpi-period">With pending fees</span>
        </div>
    </div>
</div>

<!-- Charts Row -->
<div class="charts-row">
    <div class="chart-card">
        <div class="chart-header"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M3 3v18h18"/><path d="M18 17V9M12 17V5M6 17v-3"/></svg><h3>Monthly Collection Trend</h3></div>
        <canvas id="trendChart" height="200"></canvas>
        <div id="trendChartEmpty" class="empty-row" style="display:none;">No data available</div>
    </div>
    <div class="chart-card">
        <div class="chart-header"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/><path d="M12 8v4l2 2"/></svg><h3>Payment Mode Distribution</h3></div>
        <canvas id="modeChart" height="200"></canvas>
        <div id="modeChartEmpty" class="empty-row" style="display:none;">No data available</div>
    </div>
</div>
<div class="charts-row">
    <div class="chart-card">
        <div class="chart-header"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M4 4v16h16"/><rect x="8" y="10" width="3" height="6" rx="1"/><rect x="13" y="6" width="3" height="10" rx="1"/></svg><h3>Class‑wise Pending Fees</h3></div>
        <canvas id="classChart" height="200"></canvas>
        <div id="classChartEmpty" class="empty-row" style="display:none;">No data available</div>
    </div>
    <div class="chart-card">
        <div class="chart-header"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2z"/></svg><h3>Top Defaulters</h3></div>
        <div class="top-defaulters-list" id="topDefList">
            {% for d in top_defaulters %}
            <div class="defaulter-item"><span class="defaulter-name">{{ d.student.name }} ({{ d.student.roll_number }})</span><span class="defaulter-amount">₹{{ d.pending|floatformat:2 }}</span></div>
            {% empty %}
            <div class="empty-small">No defaulters</div>
            {% endfor %}
        </div>
    </div>
</div>

<!-- Tabs -->
<div class="tabs">
    <a href="?type=collection{% if start_date %}&start_date={{ start_date|date:'Y-m-d' }}&end_date={{ end_date|date:'Y-m-d' }}{% endif %}{% if search_query %}&search={{ search_query }}{% endif %}{% if quick_filter %}&quick_filter={{ quick_filter }}{% endif %}" class="tab {% if report_type == 'collection' %}active{% endif %}">Collection Details</a>
    <a href="?type=defaulters" class="tab {% if report_type == 'defaulters' %}active{% endif %}">Defaulters List</a>
</div>

{% if report_type == 'collection' %}
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
</div>
{% else %}
<div class="table-card">
    <div class="table-header">
        <h3>All Defaulters</h3>
        <div class="table-total">{{ defaulters_data|length }} students</div>
    </div>
    <div class="table-responsive">
        <table class="data-table">
            <thead><tr><th>Roll No</th><th>Student Name</th><th>Father Name</th><th>Class</th><th>Pending Amount</th><th>Overdue Days</th><th>Action</th></tr></thead>
            <tbody>
                {% for d in defaulters_data %}
                <tr>
                    <td>{{ d.student.roll_number }}</td>
                    <td><strong>{{ d.student.name }}</strong><br><span class="student-meta">{{ d.student.grade }} - {{ d.student.section }}</span></td>
                    <td>{{ d.student.father_name }}</td>
                    <td>{{ d.student.grade }}</td>
                    <td class="pending">₹{{ d.pending_amount|floatformat:2 }}</td>
                    <td><span class="overdue-badge {% if d.days_overdue > 90 %}critical{% elif d.days_overdue > 60 %}high{% else %}medium{% endif %}">{{ d.days_overdue }} days</span></td>
                    <td class="action-btns">
                        <a href="{% url 'student_profile' schema_name=tenant.schema_name student_id=d.student.id %}" class="action-icon" title="Profile"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/><path d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/></svg></a>
                        <a href="{% url 'fee_collection' schema_name=tenant.schema_name student_id=d.student.id %}" class="action-icon" title="Collect"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2z"/></svg></a>
                    </td>
                </tr>
                {% empty %}
                <tr><td colspan="7" class="empty-row">No defaulters found</td></tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>
{% endif %}

<script>
document.addEventListener('DOMContentLoaded', function() {
    const monthlyData = {{ monthly_data|safe }};
    if (monthlyData && monthlyData.length > 0 && monthlyData.some(item => item.amount > 0)) {
        const ctx = document.getElementById('trendChart').getContext('2d');
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: monthlyData.map(item => item.month),
                datasets: [{
                    label: 'Collection (₹)',
                    data: monthlyData.map(item => item.amount),
                    borderColor: '#3b82f6',
                    backgroundColor: 'rgba(59,130,246,0.1)',
                    fill: true,
                    tension: 0.3
                }]
            },
            options: { responsive: true, maintainAspectRatio: true }
        });
    } else {
        document.getElementById('trendChart').style.display = 'none';
        document.getElementById('trendChartEmpty').style.display = 'block';
    }

    const modeData = {{ mode_distribution|safe }};
    if (modeData && modeData.length > 0) {
        const ctx = document.getElementById('modeChart').getContext('2d');
        new Chart(ctx, {
            type: 'pie',
            data: {
                labels: modeData.map(item => item.name),
                datasets: [{
                    data: modeData.map(item => item.amount),
                    backgroundColor: ['#3b82f6', '#10b981', '#f59e0b', '#ef4444']
                }]
            }
        });
    } else {
        document.getElementById('modeChart').style.display = 'none';
        document.getElementById('modeChartEmpty').style.display = 'block';
    }

    const classData = {{ class_pending|safe }};
    if (classData && classData.length > 0) {
        const ctx = document.getElementById('classChart').getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: classData.map(item => item.grade),
                datasets: [{
                    label: 'Pending (₹)',
                    data: classData.map(item => item.pending),
                    backgroundColor: '#ef4444',
                    borderRadius: 6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                scales: { y: { beginAtZero: true, title: { display: true, text: '₹' } } }
            }
        });
    } else {
        document.getElementById('classChart').style.display = 'none';
        document.getElementById('classChartEmpty').style.display = 'block';
    }
});
</script>
{% endblock %}
EOF

echo "✅ $TEMPLATE_FILE updated."

# 3. Replace the reports view in views.py using a Python one-liner
echo "✍️  Updating reports function in $VIEWS_FILE ..."

python3 << 'PYTHON_SCRIPT'
import re
import sys

view_file = "axis_saas/views.py"

with open(view_file, "r") as f:
    content = f.read()

# Find the start of the reports function
start_pattern = r'^def reports\(request, schema_name\):'
match = re.search(start_pattern, content, re.MULTILINE)
if not match:
    print("❌ Could not find 'def reports' in views.py. Aborting.")
    sys.exit(1)

start_pos = match.start()

# Find the next top-level function definition (at same indent level) or end of file
next_func_pattern = r'^\ndef [a-zA-Z_]\w*\(.*\):'
next_match = re.search(next_func_pattern, content[start_pos+1:], re.MULTILINE)
if next_match:
    end_pos = start_pos + 1 + next_match.start()
else:
    end_pos = len(content)

# New reports function code (indented correctly)
new_func = '''def reports(request, schema_name):
    tenant = get_tenant(request, schema_name)
    report_type = request.GET.get('type', 'collection')
    today = date.today()
    quick_filter = request.GET.get('quick_filter')
    start_date_str = request.GET.get('start_date')
    end_date_str = request.GET.get('end_date')
    search_q = request.GET.get('search', '').strip()
    
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
        # Default to all time if any payments exist, else last 6 months
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
            'payments': payments_qs.order_by('-payment_date'),
            'total': total_collection,
            'payment_count': payment_count,
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
            'total_collection_all': total_collection_all,
        }
    return render(request, 'tenant/reports.html', context)
'''

# Replace the function
new_content = content[:start_pos] + new_func + content[end_pos:]

# Write back
with open(view_file, "w") as f:
    f.write(new_content)

print("✅ reports function replaced successfully.")
PYTHON_SCRIPT

echo ""
echo "🎉 All done! Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
echo ""
echo "Then visit http://localhost:8000/portal/scc/reports/ to see the new reports page."
