#!/bin/bash

echo "🔧 Fixing Recent Payments display in Fee Collection..."

# ----------------------------------------------------------------------
# 1. Update views.py to include total payments count for debugging
# ----------------------------------------------------------------------
if ! grep -q "total_payments_count" axis_saas/views.py; then
    echo "➜ Adding total_payments_count to fee_collection context"
    sed -i '/recent_payments = PaymentTransaction.objects.select_related/i \        total_payments_count = PaymentTransaction.objects.count()' axis_saas/views.py
    sed -i '/\"pending_students\": pending_students_page,/a \            \"total_payments_count\": total_payments_count,' axis_saas/views.py
else
    echo "✓ total_payments_count already present"
fi

# ----------------------------------------------------------------------
# 2. Update fee_collection.html to show diagnostic info and better empty state
# ----------------------------------------------------------------------
cat > /tmp/fee_collection_patch.html << 'EOF'
<!-- Recent Payments History (Last 5 payments) -->
<div class="history-card">
    <div class="card-header">
        <h3>Recent Payments (Last 5)</h3>
        <a href="{% url 'reports' schema_name=tenant.schema_name %}?type=collection" class="view-all">View All →</a>
    </div>
    <div class="table-responsive">
        <table class="data-table">
            <thead><tr><th>Receipt</th><th>Student</th><th>Amount</th><th>Date</th><th>Mode</th><th>Receipt</th></tr></thead>
            <tbody>
                {% for p in recent_payments %}
                <tr>
                    <td><code>{{ p.receipt_number }}</code></td>
                    <td>{{ p.student.name }} ({{ p.student.roll_number }})<br><small>{{ p.student.grade }} - {{ p.student.section }}</small></td>
                    <td class="amount">₹{{ p.amount|floatformat:2 }}</td>
                    <td>{{ p.payment_date|date:"d M Y" }}</td>
                    <td>{{ p.get_payment_mode_display }}</td>
                    <td><a href="{% url 'fee_receipt' schema_name=tenant.schema_name receipt_id=p.id %}" class="receipt-link">View</a></td>
                </tr>
                {% empty %}
                <tr><td colspan="6" class="empty-row">
                    No payments recorded yet.
                    {% if total_payments_count == 0 %}
                        <br><small>💡 You haven't collected any fees. Use the form above to collect a fee.</small>
                    {% else %}
                        <br><small>⚠️ There are {{ total_payments_count }} payment(s) in the system, but they are not showing. Please contact support.</small>
                    {% endif %}
                </td></tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>
EOF

# Replace the recent payments section in the template
# We need to locate the existing history-card and replace it
# Using awk/sed to replace between markers
sed -i '/<!-- Recent Payments History/,/<\/div>/ {
    /<!-- Recent Payments History/ {
        r /tmp/fee_collection_patch.html
        d
    }
    /<\/div>/ d
}' templates/tenant/fee_collection.html

# Clean up
rm /tmp/fee_collection_patch.html

echo "✅ Fix applied. Restart Django server and hard refresh the Fee Collection page."
echo "📌 Now the Recent Payments section will show the total payment count and a more informative message if empty."
