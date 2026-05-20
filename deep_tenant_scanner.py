#!/usr/bin/env python3
import os
import sys
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
django.setup()

from django.db import connection
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, Student
from django.contrib.auth import get_user_model

print("="*60)
print("DEEP TENANT SCANNER - AXIS SCHOOL SYSTEM")
print("="*60)

# 1. List all schemas in PostgreSQL (except system)
print("\n[1] PostgreSQL Schemas (non-public):")
with connection.cursor() as cur:
    cur.execute("""
        SELECT schema_name FROM information_schema.schemata 
        WHERE schema_name NOT IN ('public', 'information_schema', 'pg_catalog', 'pg_toast')
        ORDER BY schema_name
    """)
    schemas = [row[0] for row in cur.fetchall()]
    if schemas:
        for s in schemas:
            print(f"    - {s}")
    else:
        print("    None found!")

# 2. Check tenants registered in SchoolClient (public schema)
print("\n[2] Tenants in SchoolClient table (public schema):")
tenants = SchoolClient.objects.filter(schema_name__in=schemas) if schemas else SchoolClient.objects.none()
if tenants.exists():
    for t in tenants:
        print(f"    - {t.schema_name} (name='{t.name}', active={t.is_active})")
else:
    print("    No tenants found!")

# 3. For each tenant schema, check if Student table exists and count
print("\n[3] Student counts per tenant schema:")
if schemas:
    for schema in schemas:
        try:
            with schema_context(schema):
                # Check if Student table exists in this schema
                with connection.cursor() as cur:
                    cur.execute("""
                        SELECT EXISTS (
                            SELECT 1 FROM information_schema.tables 
                            WHERE table_schema=%s AND table_name='axis_saas_student'
                        )
                    """, [schema])
                    exists = cur.fetchone()[0]
                if exists:
                    with schema_context(schema):
                        cnt = Student.objects.count()
                    print(f"    {schema:15} : {cnt} students (table exists)")
                else:
                    print(f"    {schema:15} : NO Student table (migrations incomplete?)")
        except Exception as e:
            print(f"    {schema:15} : ERROR - {str(e)[:80]}")
else:
    print("    No schemas to check.")

# 4. Check public schema for any student table (should not exist)
print("\n[4] Public schema student table check:")
with connection.cursor() as cur:
    cur.execute("""
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema='public' AND table_name='axis_saas_student'
        )
    """)
    public_exists = cur.fetchone()[0]
    if public_exists:
        cur.execute("SELECT COUNT(*) FROM axis_saas_student")
        public_cnt = cur.fetchone()[0]
        print(f"    ⚠️ WARNING: public schema has axis_saas_student table with {public_cnt} rows! (This is the leak source)")
    else:
        print("    ✅ No student table in public schema (good)")

# 5. Check if each tenant schema has all required tables (admin, auth, etc.)
print("\n[5] Tenant schema completeness check (sample tables):")
required_tables = ['axis_saas_student', 'auth_user', 'django_admin_log']
for schema in schemas[:5]:  # limit to first 5 to avoid spam
    print(f"    Schema '{schema}':")
    with schema_context(schema):
        with connection.cursor() as cur:
            for table in required_tables:
                cur.execute("""
                    SELECT EXISTS (
                        SELECT 1 FROM information_schema.tables 
                        WHERE table_schema=%s AND table_name=%s
                    )
                """, [schema, table])
                exists = cur.fetchone()[0]
                status = "✅" if exists else "❌"
                print(f"        {status} {table}")

# 6. Test schema switching via middleware simulation
print("\n[6] Testing manual schema switching (simulating request):")
if schemas:
    test_schema = schemas[0]
    print(f"    Switching to schema '{test_schema}' via connection.set_schema()...")
    try:
        connection.set_schema(test_schema)
        with connection.cursor() as cur:
            cur.execute("SELECT current_schema()")
            current = cur.fetchone()[0]
        print(f"    Current schema after set_schema: {current}")
        # Now query Student
        cnt = Student.objects.count()
        print(f"    Student count in {test_schema}: {cnt}")
    except Exception as e:
        print(f"    Error: {e}")
    finally:
        connection.set_schema('public')
        print("    Reset to public schema.")

# 7. Recommendation
print("\n" + "="*60)
print("RECOMMENDATION:")
if public_exists and public_cnt > 0:
    print("🚨 CRITICAL: Student data is stored in PUBLIC schema, not tenant schemas.")
    print("   This means your views are not switching schemas. Fix: Ensure middleware is active")
    print("   and that you use 'with schema_context(tenant.schema_name):' in all tenant views.")
elif schemas and any(True for s in schemas if 'student' in str(s).lower()):  # heuristic
    print("✅ Tenant schemas exist and have student tables. Check if views are using schema_context.")
else:
    print("⚠️ No tenant schemas found or student tables missing. Run migrations for each tenant:")
    print("   python manage.py migrate_schemas --tenant")
print("="*60)
