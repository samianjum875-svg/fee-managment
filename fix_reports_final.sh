#!/bin/bash

# fix_reports_final.sh - Restores working reports page with pagination
# Run from: ~/axis_school_sys

set -e

VIEWS_FILE="axis_saas/views.py"
TEMPLATE_FILE="templates/tenant/reports.html"
BACKUP_FILE="templates/tenant/reports.html.bak"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file $BACKUP_FILE not found. Cannot restore."
    exit 1
fi

echo "📁 Restoring original reports.html from backup..."
cp "$BACKUP_FILE" "$TEMPLATE_FILE"
echo "✅ Restored."

# ----------------------------------------------------------------------
# 1. Fix the duplicated reports view in views.py
# ----------------------------------------------------------------------
echo "✍️  Cleaning up duplicated code in reports view..."

python3 << 'PYTHON_SCRIPT'
import re

view_file = "axis_saas/views.py"

with open(view_file, "r") as f:
    content = f.read()

# The current reports function has a duplicate (two definitions). We need to replace the whole function
# with a clean version (the one that already includes pagination, which we added earlier).
# The clean version is the first one with pagination (the one that uses page_num and Paginator).
# We'll locate and keep only that version, removing any extra copies.

# Find the start of the reports function
pattern = r'^def reports\(request, schema_name\):.*?(?=^def [a-zA-Z_]|$)'
matches = list(re.finditer(pattern, content, re.DOTALL | re.MULTILINE))
if len(matches) == 0:
    print("❌ Could not find reports function.")
    exit(1)

# The first match should be the correct one (the one we previously added with pagination)
correct_func = matches[0].group(0)

# Now replace the entire content from the first match to the end of the last match
# to ensure only one copy remains.
last_match = matches[-1]
new_content = content[:matches[0].start()] + correct_func + content[last_match.end():]

with open(view_file, "w") as f:
    f.write(new_content)

print("✅ Cleaned up reports view.")
PYTHON_SCRIPT

# ----------------------------------------------------------------------
# 2. Apply pagination to the restored reports.html
# ----------------------------------------------------------------------
echo "✍️  Adding pagination to the restored reports.html..."

python3 << 'PYTHON_SCRIPT'
import re

template_file = "templates/tenant/reports.html"

with open(template_file, "r") as f:
    content = f.read()

# Locate the Transaction History table section (inside the collection block)
# We'll replace the entire block from the start of the table-card to the end of the collection block.
# A safer approach: replace the whole {% if report_type == 'collection' %} block with a version that includes pagination.

# Find the start and end of the collection block
start_marker = "{% if report_type == 'collection' %}"
end_marker = "{% else %}"
start_idx = content.find(start_marker)
if start_idx == -1:
    print("❌ Could not find collection block start.")
    exit(1)
end_idx = content.find(end_marker, start_idx)
if end_idx == -1:
    print("❌ Could not find else tag.")
    exit(1)

# Build new collection block with pagination
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
        <tr>
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
new_content = content[:start_idx] + new_collection_block + content[end_idx + len(end_marker):]
# Ensure the {% else %} block remains correctly closed by the original {% endif %} later in the file.
# The original file has an {% endif %} after the else block, which we keep.

with open(template_file, "w") as f:
    f.write(new_content)

print("✅ Pagination added to reports.html.")
PYTHON_SCRIPT

echo ""
echo "🎉 Fix complete! Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
echo ""
echo "The reports page should now work correctly with pagination."
