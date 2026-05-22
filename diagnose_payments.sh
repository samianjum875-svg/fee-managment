#!/bin/bash

echo "═══════════════════════════════════════════════════════════════"
echo "🔍 AXIS SCHOOL SYSTEM - PAYMENT HISTORY DIAGNOSTIC SCANNER"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ------------------------------------------------------------------
# 1. Environment check
# ------------------------------------------------------------------
echo "📌 STEP 1: Checking Django environment"
if [ ! -f "manage.py" ]; then
    echo "❌ Error: manage.py not found. Run this script from the project root (where manage.py is)."
    exit 1
fi

# Check if virtual env is active
if [ -z "$VIRTUAL_ENV" ]; then
    echo "⚠️  Warning: No virtual environment detected. Activate it first: source venv/bin/activate"
fi

# ------------------------------------------------------------------
# 2. Create a Python diagnostic script
# ------------------------------------------------------------------
cat > /tmp/diagnose_payments.py << 'PYEOF'
import os
import sys
import django
from datetime import datetime

# Setup Django
sys.path.insert(0, os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
django.setup()

from django.db import connection, connections
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, PaymentTransaction, Student
from django.contrib.auth.models import User

print("\n" + "="*70)
print("📊 DATABASE & TENANT ANALYSIS")
print("="*70)

# ------------------------------------------------------------------
# 2.1 Database connection test
# ------------------------------------------------------------------
try:
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1")
    print("✅ Database connection: OK")
except Exception as e:
    print(f"❌ Database connection FAILED: {e}")
    sys.exit(1)

# ------------------------------------------------------------------
# 2.2 List all schemas
# ------------------------------------------------------------------
print("\n📌 ALL SCHEMAS IN DATABASE:")
with connection.cursor() as cursor:
    cursor.execute("SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT LIKE 'pg_%' AND schema_name != 'information_schema' ORDER BY schema_name;")
    schemas = [row[0] for row in cursor.fetchall()]
    for s in schemas:
        print(f"  - {s}")

# ------------------------------------------------------------------
# 2.3 Tenants and their schemas
# ------------------------------------------------------------------
print("\n📌 TENANTS (SchoolClient):")
tenants = SchoolClient.objects.filter(is_active=True).exclude(schema_name='public')
for tenant in tenants:
    print(f"  - {tenant.name} (schema: {tenant.schema_name})")

# ------------------------------------------------------------------
# 2.4 Count PaymentTransaction records in each schema
# ------------------------------------------------------------------
print("\n📌 PAYMENTTRANSACTION RECORDS PER SCHEMA:")
total_payments_all_schemas = 0
payment_counts = {}

for schema in schemas:
    try:
        with schema_context(schema):
            count = PaymentTransaction.objects.count()
            payment_counts[schema] = count
            total_payments_all_schemas += count
            print(f"  {schema}: {count} payment(s)")
    except Exception as e:
        print(f"  {schema}: ERROR - {e}")

print(f"\n  ➤ TOTAL payments across all schemas: {total_payments_all_schemas}")

# ------------------------------------------------------------------
# 2.5 Check the current tenant's payments (from session)
# ------------------------------------------------------------------
# We need to simulate a request to get the tenant from session.
# Instead, we'll check each tenant individually.
print("\n📌 PAYMENTS PER TENANT (with schema_context):")
for tenant in tenants:
    with schema_context(tenant.schema_name):
        payments = PaymentTransaction.objects.all()
        count = payments.count()
        if count > 0:
            print(f"  ✅ {tenant.schema_name}: {count} payment(s)")
            # Show the first 3 payments as sample
            for p in payments[:3]:
                print(f"      - {p.receipt_number} | {p.student.name} | ₹{p.amount} | {p.payment_date}")
        else:
            print(f"  ⚠️ {tenant.schema_name}: 0 payments")

# ------------------------------------------------------------------
# 2.6 Check if there are any students with pending fee records
# ------------------------------------------------------------------
print("\n📌 PENDING FEE RECORDS (per tenant):")
for tenant in tenants:
    with schema_context(tenant.schema_name):
        pending_records = sum(1 for fr in FeeRecord.objects.filter(status__in=['pending', 'partial', 'overdue']) if fr.remaining > 0)
        print(f"  {tenant.schema_name}: {pending_records} pending fee record(s)")

# ------------------------------------------------------------------
# 2.7 Test the exact query used in fee_collection view
# ------------------------------------------------------------------
print("\n📌 TESTING recent_payments QUERY (LAST 5) FOR EACH TENANT:")
for tenant in tenants:
    with schema_context(tenant.schema_name):
        recent = PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:5]
        count = recent.count()
        print(f"  {tenant.schema_name}: {count} recent payment(s)")
        if count == 0 and PaymentTransaction.objects.count() > 0:
            print(f"     ❌ WARNING: There are payments but recent query returned 0! Check order_by/pagination.")
        for p in recent:
            print(f"     - {p.receipt_number} | {p.student.name} | {p.payment_date}")

# ------------------------------------------------------------------
# 2.8 Check middleware configuration
# ------------------------------------------------------------------
print("\n📌 MIDDLEWARE INSPECTION:")
from django.conf import settings
middleware = settings.MIDDLEWARE
for m in middleware:
    if 'schema' in m.lower() or 'tenant' in m.lower() or 'middleware_session' in m:
        print(f"  - {m}")
if 'axis_saas.middleware.PublicSchemaMiddleware' in middleware:
    print("  ⚠️ WARNING: PublicSchemaMiddleware is still active! This breaks tenant isolation.")
else:
    print("  ✅ PublicSchemaMiddleware not found (good)")

# Check SafeSessionMiddleware
if 'axis_saas.middleware_session.SafeSessionMiddleware' in middleware:
    print("  ℹ️ SafeSessionMiddleware is present (may interfere with session saving)")
else:
    print("  ℹ️ SafeSessionMiddleware not in MIDDLEWARE")

# ------------------------------------------------------------------
# 2.9 Check signals
# ------------------------------------------------------------------
print("\n📌 SIGNALS CHECK:")
from axis_saas import signals
import inspect
for name, obj in inspect.getmembers(signals):
    if inspect.isfunction(obj) and name.startswith('provision_') or name.startswith('sync_'):
        print(f"  - Signal: {name}")
# Check if any signal modifies PaymentTransaction after save
print("  (No signals directly affecting PaymentTransaction found)")

# ------------------------------------------------------------------
# 2.10 Check for any custom admin or form overrides
# ------------------------------------------------------------------
print("\n📌 CUSTOM FORM VALIDATION:")
try:
    from axis_saas.forms import PaymentTransaction
    print("  ⚠️ PaymentTransaction form found? Unexpected.")
except ImportError:
    print("  ✅ No custom PaymentTransaction form")

# ------------------------------------------------------------------
# 2.11 Check if any payment records exist in public schema that should be in tenant
# ------------------------------------------------------------------
print("\n📌 PAYMENTS IN PUBLIC SCHEMA (should be zero):")
with schema_context('public'):
    public_payments = PaymentTransaction.objects.count()
    if public_payments > 0:
        print(f"  ❌ CRITICAL: {public_payments} payment(s) found in public schema!")
        print("     These payments will NEVER appear in tenant portals.")
        print("     You need to migrate them to the correct tenant schema.")
    else:
        print("  ✅ No payments in public schema")

# ------------------------------------------------------------------
# 2.12 Check if student foreign keys are valid across schemas
# ------------------------------------------------------------------
print("\n📌 CROSS-SCHEMA FOREIGN KEY INTEGRITY:")
for tenant in tenants:
    with schema_context(tenant.schema_name):
        # Get all PaymentTransaction students
        student_ids = set(PaymentTransaction.objects.values_list('student_id', flat=True).distinct())
        missing = []
        for sid in student_ids:
            if not Student.objects.filter(id=sid).exists():
                missing.append(sid)
        if missing:
            print(f"  ❌ {tenant.schema_name}: {len(missing)} payment(s) reference non-existent student(s): {missing[:5]}")
        else:
            print(f"  ✅ {tenant.schema_name}: All student references valid")

# ------------------------------------------------------------------
# 2.13 Final summary
# ------------------------------------------------------------------
print("\n" + "="*70)
print("📋 FINAL DIAGNOSTIC SUMMARY")
print("="*70)
print(f"Total payments across all schemas: {total_payments_all_schemas}")
if total_payments_all_schemas == 0:
    print("❌ NO PAYMENTS FOUND ANYWHERE in the database.")
    print("   Possible causes:")
    print("   1. You haven't collected any fees yet.")
    print("   2. Fee records exist but payments were not created (check fee collection form).")
    print("   3. PaymentTransaction model is not being saved correctly.")
elif total_payments_all_schemas > 0 and all(payment_counts.get(t.schema_name, 0) == 0 for t in tenants):
    print("❌ Payments exist but all are in the public schema!")
    print("   Solution: Migrate payments from public schema to each tenant schema.")
elif any(payment_counts.get(t.schema_name, 0) > 0 for t in tenants):
    print("✅ Some tenants have payments. If they don't show in UI, check:")
    print("   - The recent_payments query uses order_by('-payment_date') – ensure payment_date is set.")
    print("   - The template may be using an empty context variable.")
    print("   - Check that the view passes 'recent_payments' to the template.")

print("\n🔧 To see raw payments in a specific tenant, run:")
print("   python manage.py shell")
print("   from axis_saas.models import PaymentTransaction")
print("   from django_tenants.utils import schema_context")
print("   with schema_context('your_schema_name'):")
print("       print(PaymentTransaction.objects.count())")
print("       for p in PaymentTransaction.objects.all()[:5]: print(p.receipt_number, p.amount)")
print("\n═══════════════════════════════════════════════════════════════")
PYEOF

# ------------------------------------------------------------------
# 3. Run the Python script
# ------------------------------------------------------------------
echo "📡 Running diagnostic..."
python3 /tmp/diagnose_payments.py

echo ""
echo "✅ Diagnostic complete. Copy the output above and share it."
echo "   Based on the report, we'll identify the exact fix."
