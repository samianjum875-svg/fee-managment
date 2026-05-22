#!/bin/bash
# AXIS SCHOOL SYSTEM – COMPLETE FIX PATCHER
# Run this from your project root (where manage.py is)

set -e

echo "============================================="
echo "🔧 1. Creating session directory"
echo "============================================="
sudo mkdir -p /tmp/django_sessions/
sudo chmod 777 /tmp/django_sessions/

echo "============================================="
echo "🔧 2. Adding SafeSessionMiddleware (if missing)"
echo "============================================="
MIDDLEWARE_FILE="axis_saas/settings.py"
if ! grep -q "axis_saas.middleware_session.SafeSessionMiddleware" "$MIDDLEWARE_FILE"; then
    # Insert after TenantMainMiddleware
    sed -i '/django_tenants.middleware.main.TenantMainMiddleware/a \    \x27axis_saas.middleware_session.SafeSessionMiddleware\x27,' "$MIDDLEWARE_FILE"
    echo "✅ Middleware added."
else
    echo "✅ Middleware already present."
fi

echo "============================================="
echo "🔧 3. Running migrations for ALL schemas"
echo "============================================="
python manage.py migrate_schemas --shared
python manage.py migrate_schemas --tenant

echo "============================================="
echo "🔧 4. Collecting static files"
echo "============================================="
python manage.py collectstatic --noinput

echo "============================================="
echo "✅ ALL FIXES APPLIED SUCCESSFULLY"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Restart your Django server:"
echo "       python manage.py runserver"
echo "  2. Login to any school portal (e.g., /portal/as/)."
echo "  3. Navigate to Fee Collection / Reports – payments will now appear."
echo ""
echo "If you still see empty tables, run this debug command:"
echo "   python manage.py shell -c \"from axis_saas.models import PaymentTransaction; print(PaymentTransaction.objects.all())\""
echo ""
