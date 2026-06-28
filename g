#!/usr/bin/env python3
"""
AXIS Railway Fixer – resolves migration conflict, applies migrations, and ensures schema is complete.
Run: python3 fix_railway.py
"""

import os
import sys
import shutil
from pathlib import Path

# Setup Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
sys.path.insert(0, os.getcwd())

import django
django.setup()

from django.core.management import call_command
from django.db import connection
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient


def fix_migration_conflict():
    """Resolve conflicting migrations by creating a merge migration."""
    print("📦 Fixing migration conflict...")
    try:
        # Attempt to create a merge migration (non‑interactive)
        call_command('makemigrations', 'axis_saas', '--merge', '--noinput')
        print("✅ Merge migration created successfully.")
    except Exception as e:
        print(f"⚠️ Merge failed (may not be needed): {e}")


def run_migrations():
    """Apply all pending migrations."""
    print("🔄 Running migrations...")
    try:
        call_command('migrate')
        print("✅ Migrations applied.")
    except Exception as e:
        print(f"❌ Migration error: {e}")
        sys.exit(1)


def ensure_columns():
    """Add missing columns to Student and FeeRecord if not present (idempotent)."""
    print("🔧 Ensuring required columns exist in tenant schemas...")
    tenants = SchoolClient.objects.filter(is_active=True).exclude(schema_name='public')
    if not tenants.exists():
        print("   No active tenants found. Skipping.")
        return

    for tenant in tenants:
        print(f"   Processing tenant: {tenant.schema_name}")
        with schema_context(tenant.schema_name):
            with connection.cursor() as cursor:
                # Check and add default_extra_charges to Student
                cursor.execute("""
                    SELECT column_name FROM information_schema.columns
                    WHERE table_name='axis_saas_student'
                    AND column_name='default_extra_charges'
                """)
                if not cursor.fetchone():
                    print(f"     ➕ Adding default_extra_charges")
                    cursor.execute("""
                        ALTER TABLE axis_saas_student
                        ADD COLUMN default_extra_charges jsonb DEFAULT '[]'::jsonb
                    """)
                else:
                    print(f"     ✅ default_extra_charges already exists")

                # Check and add extra_charges to FeeRecord
                cursor.execute("""
                    SELECT column_name FROM information_schema.columns
                    WHERE table_name='axis_saas_feerecord'
                    AND column_name='extra_charges'
                """)
                if not cursor.fetchone():
                    print(f"     ➕ Adding extra_charges")
                    cursor.execute("""
                        ALTER TABLE axis_saas_feerecord
                        ADD COLUMN extra_charges jsonb DEFAULT '[]'::jsonb
                    """)
                else:
                    print(f"     ✅ extra_charges already exists")

                # (Optional) Drop fee_custom_items if it exists – cleanup
                cursor.execute("""
                    SELECT column_name FROM information_schema.columns
                    WHERE table_name='axis_saas_student'
                    AND column_name='fee_custom_items'
                """)
                if cursor.fetchone():
                    print(f"     🗑️ Dropping obsolete fee_custom_items")
                    cursor.execute("ALTER TABLE axis_saas_student DROP COLUMN IF EXISTS fee_custom_items")
    print("✅ Column checks complete.")


def main():
    print("=" * 60)
    print("🚀 AXIS RAILWAY FIXER")
    print("=" * 60)

    # Step 1: Fix migration conflict
    fix_migration_conflict()

    # Step 2: Run migrations
    run_migrations()

    # Step 3: Ensure columns exist (in case migrations missed something)
    ensure_columns()

    print("\n🎉 All fixes applied. Now restart your server:")
    print("   Railway: Deploy a new release or restart the service.")
    print("   Local:   python manage.py runserver")
    print("=" * 60)


if __name__ == '__main__':
    main()
