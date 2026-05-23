#!/bin/bash

# fix_debug_api.sh - Adds missing debug_payments_api view to axis_saas/views.py
# Run from: ~/axis_school_sys

set -e

VIEWS_FILE="axis_saas/views.py"

if [ ! -f "$VIEWS_FILE" ]; then
    echo "ERROR: $VIEWS_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup original
if [ ! -f "${VIEWS_FILE}.bak" ]; then
    cp "$VIEWS_FILE" "${VIEWS_FILE}.bak"
    echo "✅ Backup saved as ${VIEWS_FILE}.bak"
fi

# Check if function already exists
if grep -q "^def debug_payments_api(" "$VIEWS_FILE"; then
    echo "debug_payments_api already exists. Nothing to do."
    exit 0
fi

echo "✍️  Appending debug_payments_api to $VIEWS_FILE ..."

cat >> "$VIEWS_FILE" << 'EOF'

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
EOF

echo "✅ debug_payments_api added successfully."
echo ""
echo "🚀 Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
