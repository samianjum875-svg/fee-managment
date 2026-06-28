#!/usr/bin/env python3
"""
Drop the extra column 'fee_custom_items' from all tenant schemas.
Run: python3 drop_fee_custom_items.py
"""
import os
import sys
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
django.setup()

from django.db import connection
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient

def drop_column_from_schema(schema_name, table_name, column_name):
    with schema_context(schema_name):
        with connection.cursor() as cursor:
            # Check if column exists
            cursor.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_schema = %s AND table_name = %s AND column_name = %s
            """, [schema_name, table_name, column_name])
            if cursor.fetchone():
                cursor.execute(f"ALTER TABLE {table_name} DROP COLUMN {column_name} CASCADE")
                print(f"✅ Dropped column '{column_name}' from {schema_name}.{table_name}")
            else:
                print(f"ℹ️ Column '{column_name}' not found in {schema_name}.{table_name}")

def main():
    tenants = SchoolClient.objects.exclude(schema_name='public')
    print(f"Found {tenants.count()} tenant schemas.")
    for tenant in tenants:
        drop_column_from_schema(tenant.schema_name, 'axis_saas_student', 'fee_custom_items')
    print("✅ Done.")

if __name__ == '__main__':
    main()
