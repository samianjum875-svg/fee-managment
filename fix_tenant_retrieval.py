import re

file_path = "axis_saas/public_urls.py"

with open(file_path, "r") as f:
    content = f.read()

# Fix get_school_tenant to use public schema explicitly
old_get = """def get_school_tenant(schema_name):
    schema_name = schema_name.lower().strip()
    tenant = SchoolClient.objects.filter(schema_name__iexact=schema_name, is_active=True).first()
    return tenant"""

new_get = """def get_school_tenant(schema_name):
    schema_name = schema_name.lower().strip()
    from django_tenants.utils import schema_context
    with schema_context('public'):
        tenant = SchoolClient.objects.filter(schema_name__iexact=schema_name, is_active=True).first()
    return tenant"""

if old_get in content:
    content = content.replace(old_get, new_get)
    print("✅ Patched get_school_tenant to use public schema")
else:
    print("⚠️ Could not find old function, trying regex...")
    content = re.sub(
        r'def get_school_tenant\(schema_name\):.*?return tenant',
        new_get,
        content,
        flags=re.DOTALL
    )

# Also ensure all views that call get_school_tenant don't have schema_context interfering elsewhere
# Already handled by the above, as now tenant fetch is in public schema.

with open(file_path, "w") as f:
    f.write(content)

print("Fix complete. Restart server now.")
