#!/bin/bash

echo "═══════════════════════════════════════════════════════════════"
echo "🔧 FINAL CORRECTED FIX – Resolving syntax error & payment display"
echo "═══════════════════════════════════════════════════════════════"

# ------------------------------------------------------------------
# 1. Fix the duplicate print line in views.py (syntax error)
# ------------------------------------------------------------------
echo "➜ Fixing syntax error in views.py (duplicate print)..."
sed -i '/^.*DEBUG fee_collection.*$/d' axis_saas/views.py
# Now add a single debug line properly
sed -i '/recent_payments = PaymentTransaction.objects.select_related/a\        print(f"DEBUG fee_collection: total_payments={PaymentTransaction.objects.count()}, recent_count={recent_payments.count()}")' axis_saas/views.py

# ------------------------------------------------------------------
# 2. Replace the recent_payments block in fee_collection with robust version
# ------------------------------------------------------------------
echo "➜ Replacing recent_payments logic with robust fallback..."
cat > /tmp/robust_views.py << 'PYEOF'
import re

with open('axis_saas/views.py', 'r') as f:
    content = f.read()

# Find the fee_collection function and replace the recent_payments section
# We'll locate the line "recent_payments = PaymentTransaction.objects.select_related..." and replace the block
old_block = r'(recent_payments = PaymentTransaction\.objects\.select_related\(\'student\'\)\.order_by\(-\'payment_date\'\)\[:5\]\s*print\(f"DEBUG fee_collection: total_payments=\{PaymentTransaction\.objects\.count\(\)\}, recent_count=\{recent_payments\.count\(\)\}"\))'
new_block = '''# Robust recent payments with fallback
        recent_payments = PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:5]
        total_payments_count = PaymentTransaction.objects.count()
        print(f"DEBUG fee_collection: total_payments={total_payments_count}, recent_count={recent_payments.count()}")
        if recent_payments.count() == 0 and total_payments_count > 0:
            print("WARNING: recent_payments empty but total payments > 0. Using fallback without select_related.")
            recent_payments = PaymentTransaction.objects.all().order_by('-payment_date')[:5]
            # Manually attach student objects if needed
            student_ids = [p.student_id for p in recent_payments]
            students = {s.id: s for s in Student.objects.filter(id__in=student_ids)}
            for p in recent_payments:
                if p.student_id in students:
                    p.student = students[p.student_id]
            print(f"DEBUG fallback: recent_payments now has {recent_payments.count()} records")'''

content = re.sub(old_block, new_block, content, flags=re.DOTALL)

with open('axis_saas/views.py', 'w') as f:
    f.write(content)
print("✅ views.py updated with robust recent_payments")
PYEOF

python3 /tmp/robust_views.py

# ------------------------------------------------------------------
# 3. Ensure fee_collection.html shows raw payments if fallback is used
# ------------------------------------------------------------------
echo "➜ Updating fee_collection.html to show debug info for fallback..."
# Add a small debug span in the empty section to display raw payment IDs if any
cat > /tmp/fix_template.py << 'EOF'
with open('templates/tenant/fee_collection.html', 'r') as f:
    html = f.read()

# Find the empty row section and add a debug output
if 'DEBUG: raw payments' not in html:
    debug_js = '''
        // Additional debug: if total_payments_count > 0 but recent_payments is empty, show raw payment IDs
        if ({{ total_payments_count|default:0 }} > 0 && {{ recent_payments|length }} === 0) {
            fetch('/api/debug-payments/')
                .then(r => r.json())
                .then(data => {
                    const container = document.querySelector('.history-card .empty-row');
                    if (container && data.payments && data.payments.length) {
                        const div = document.createElement('div');
                        div.style.marginTop = '10px';
                        div.style.fontSize = '11px';
                        div.style.fontFamily = 'monospace';
                        div.innerHTML = '<strong>Debug (raw payment IDs):</strong> ' + data.payments.map(p => p.receipt_number).join(', ');
                        container.appendChild(div);
                    }
                }).catch(e => console.log('Debug fetch failed', e));
        }
    '''
    # Insert before closing script tag
    html = html.replace('</script>', debug_js + '\n</script>')
    
with open('templates/tenant/fee_collection.html', 'w') as f:
    f.write(html)
print("✅ Template updated with debug output")
EOF

python3 /tmp/fix_template.py

# ------------------------------------------------------------------
# 4. Add a temporary debug API endpoint to list raw payments
# ------------------------------------------------------------------
echo "➜ Adding debug API endpoint for raw payments..."
if ! grep -q "def debug_payments_api" axis_saas/views.py; then
    cat >> axis_saas/views.py << 'EOF'

# ------------------- API: Debug Payments (raw list) -------------------
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
        data = [{'id': p.id, 'receipt_number': p.receipt_number, 'student_id': p.student_id, 'amount': float(p.amount), 'date': p.payment_date.strftime('%Y-%m-%d')} for p in payments]
        return JsonResponse({'payments': data, 'total': PaymentTransaction.objects.count()})
EOF
    # Also register the URL in public_urls.py
    sed -i "/from .views import/ s/$/, debug_payments_api/" axis_saas/public_urls.py
    sed -i "/urlpatterns = \[/a\    path('api/debug-payments/', debug_payments_api, name='debug_payments_api')," axis_saas/public_urls.py
    echo "✅ Debug API added"
fi

# ------------------------------------------------------------------
# 5. Final instructions
# ------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ FIXES APPLIED"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📌 NEXT STEPS:"
echo "   1. Restart Django server:"
echo "      python manage.py runserver"
echo ""
echo "   2. Visit the Fee Collection page for the 'ba' tenant:"
echo "      http://localhost:8000/portal/ba/fee/collection/"
echo ""
echo "   3. Open browser console (F12) and look for debug messages."
echo "      - If you see 'WARNING: recent_payments empty...' the fallback is triggered."
echo "      - If even fallback returns empty, check the database manually:"
echo ""
echo "      python manage.py shell -c \""
echo "      from axis_saas.models import PaymentTransaction"
echo "      from django_tenants.utils import schema_context"
echo "      with schema_context('ba'):"
echo "          for p in PaymentTransaction.objects.all()[:5]:"
echo "              print(p.receipt_number, p.payment_date, p.student_id)"
echo "      \""
echo ""
echo "   4. If payments have a NULL payment_date, update them:"
echo "      python manage.py shell -c \""
echo "      from axis_saas.models import PaymentTransaction"
echo "      from django_tenants.utils import schema_context"
echo "      from datetime import date"
echo "      with schema_context('ba'):"
echo "          PaymentTransaction.objects.filter(payment_date__isnull=True).update(payment_date=date.today())"
echo "      \""
echo ""
echo "   The debug API will also show raw payment details in the page."
echo "═══════════════════════════════════════════════════════════════"
