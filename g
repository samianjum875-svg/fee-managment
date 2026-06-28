#!/usr/bin/env python3
"""
AXIS Schema Fixer – adds missing columns (default_extra_charges, extra_charges)
to all tenant schemas to fix 500 error on student creation.
Run: python3 fix_schema.py
"""

import os
import sys
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
django.setup()

from django.db import connection
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient

def add_missing_columns(schema_name):
    """Add missing columns to Student and FeeRecord tables if they don't exist."""
    with schema_context(schema_name):
        with connection.cursor() as cursor:
            # Check and add default_extra_charges to Student
            cursor.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_name='axis_saas_student'
                AND column_name='default_extra_charges'
            """)
            if not cursor.fetchone():
                print(f"  ➕ Adding default_extra_charges to axis_saas_student in {schema_name}")
                cursor.execute("""
                    ALTER TABLE axis_saas_student
                    ADD COLUMN default_extra_charges jsonb DEFAULT '[]'::jsonb
                """)
            else:
                print(f"  ✅ default_extra_charges already exists in {schema_name}")

            # Check and add extra_charges to FeeRecord
            cursor.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_name='axis_saas_feerecord'
                AND column_name='extra_charges'
            """)
            if not cursor.fetchone():
                print(f"  ➕ Adding extra_charges to axis_saas_feerecord in {schema_name}")
                cursor.execute("""
                    ALTER TABLE axis_saas_feerecord
                    ADD COLUMN extra_charges jsonb DEFAULT '[]'::jsonb
                """)
            else:
                print(f"  ✅ extra_charges already exists in {schema_name}")

def main():
    print("🔧 AXIS Schema Fixer")
    print("=" * 50)

    # Get all active tenant schemas (excluding public)
    tenants = SchoolClient.objects.filter(is_active=True).exclude(schema_name='public')
    if not tenants.exists():
        print("No tenants found. Nothing to do.")
        return

    for tenant in tenants:
        print(f"\n📁 Processing tenant: {tenant.schema_name} ({tenant.name})")
        try:
            add_missing_columns(tenant.schema_name)
        except Exception as e:
            print(f"  ❌ Error: {str(e)}")

    print("\n✅ Done. All missing columns have been added.")
    print("   Restart your Django server (or Railway service) and try adding a student again.")

if __name__ == '__main__':
    main()
