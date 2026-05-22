#!/usr/bin/env python
"""
AXIS School System – Full Database Scanner
Extracts all schemas, tables, and key records for every tenant.
Run: python full_db_scan.py
"""

import os
import sys
import django

# Setup Django environment
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
django.setup()

from django.db import connection
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, Student, PaymentTransaction, FeeRecord, FeeStructure
from collections import defaultdict

def scan_all_schemas():
    print("=" * 80)
    print("AXIS SCHOOL SYSTEM – FULL DATABASE SCAN")
    print("=" * 80)

    # Get all schemas from PostgreSQL
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT schema_name 
            FROM information_schema.schemata 
            WHERE schema_name NOT LIKE 'pg_%' 
              AND schema_name != 'information_schema'
            ORDER BY schema_name;
        """)
        all_schemas = [row[0] for row in cursor.fetchall()]

    print(f"\n📂 Total schemas found: {len(all_schemas)}")
    print("-" * 80)

    # Get tenants
    tenants = {t.schema_name: t.name for t in SchoolClient.objects.filter(is_active=True).exclude(schema_name='public')}
    print("\n🏫 Active Tenants (schools):")
    for schema, name in tenants.items():
        print(f"   {schema:20} → {name}")
    print("-" * 80)

    # For each schema, collect stats
    for schema in all_schemas:
        print(f"\n🔍 SCHEMA: {schema}")
        if schema in tenants:
            print(f"   School: {tenants[schema]}")
        else:
            print("   (No associated tenant – possibly leftover or public)")

        try:
            with schema_context(schema):
                # Count tables in this schema
                with connection.cursor() as cursor:
                    cursor.execute("""
                        SELECT table_name 
                        FROM information_schema.tables 
                        WHERE table_schema = %s 
                          AND table_type = 'BASE TABLE'
                        ORDER BY table_name;
                    """, [schema])
                    tables = [row[0] for row in cursor.fetchall()]
                
                print(f"   📊 Tables: {len(tables)}")
                
                # Focus on key tables
                key_tables = {
                    'axis_saas_student': Student,
                    'axis_saas_paymenttransaction': PaymentTransaction,
                    'axis_saas_feerecord': FeeRecord,
                    'axis_saas_feestructure': FeeStructure,
                }
                
                for table_name, model in key_tables.items():
                    if table_name in tables:
                        count = model.objects.count()
                        print(f"      ✓ {table_name}: {count} record(s)")
                        if count > 0 and table_name == 'axis_saas_paymenttransaction':
                            # Show first 3 payments
                            for p in PaymentTransaction.objects.all()[:3]:
                                student_name = p.student.name if p.student else "DELETED"
                                print(f"         - {p.receipt_number} | {student_name} | ₹{p.amount} | {p.payment_date}")
                        elif count > 0 and table_name == 'axis_saas_feerecord':
                            # Show sample fee records
                            for fr in FeeRecord.objects.all()[:3]:
                                print(f"         - {fr.student.name} | {fr.month}/{fr.year} | ₹{fr.amount} | paid: ₹{fr.paid_amount}")
                    else:
                        print(f"      ✗ {table_name}: table not found")
                
                # Additional: count students with pending fees
                pending_count = Student.objects.filter(
                    fee_records__status__in=['pending', 'partial', 'overdue']
                ).distinct().count()
                print(f"      ℹ️ Students with pending fees: {pending_count}")

        except Exception as e:
            print(f"   ❌ Error accessing schema: {e}")

    print("\n" + "=" * 80)
    print("SCAN COMPLETE")
    print("=" * 80)

if __name__ == "__main__":
    scan_all_schemas()
