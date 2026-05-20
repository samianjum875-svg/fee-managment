import re
import os

SETTINGS_FILE = "axis_saas/settings.py"

# 1. Comment out CrossTenantSessionIsolationMiddleware
with open(SETTINGS_FILE, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "CrossTenantSessionIsolationMiddleware" in line and not line.strip().startswith("#"):
        new_lines.append("# " + line)
    else:
        new_lines.append(line)

with open(SETTINGS_FILE, "w") as f:
    f.writelines(new_lines)
print("✅ Commented out CrossTenantSessionIsolationMiddleware")

# 2. Add SESSION_COOKIE_PATH if missing
with open(SETTINGS_FILE, "r") as f:
    content = f.read()
if "SESSION_COOKIE_PATH" not in content:
    with open(SETTINGS_FILE, "a") as f:
        f.write("\nSESSION_COOKIE_PATH = '/'\n")
    print("✅ Added SESSION_COOKIE_PATH = '/'")
else:
    print("ℹ️ SESSION_COOKIE_PATH already present")

# 3. Patch public_urls.py to explicitly save session after login
PUBLIC_URLS = "axis_saas/public_urls.py"
with open(PUBLIC_URLS, "r") as f:
    urls_content = f.read()

# Replace the login function to ensure session is saved
old_login = """def school_login(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School not found')
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        print(f"[DEBUG] Login attempt: schema={schema_name}, username={username}, stored_user={tenant.admin_username}, stored_pass={tenant.admin_password}")
        if username == tenant.admin_username and password == tenant.admin_password:
            request.session['school_admin_authenticated'] = True
            request.session['school_admin_schema'] = tenant.schema_name
            print("[DEBUG] Login successful, session set, redirecting to dashboard")
            return redirect(f'/portal/{tenant.schema_name}/')
        print("[DEBUG] Invalid credentials")
        return render(request, 'tenant/login.html', {'tenant': tenant, 'error': 'Invalid credentials'})
    return render(request, 'tenant/login.html', {'tenant': tenant})"""

new_login = """def school_login(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School not found')
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        print(f"[DEBUG] Login attempt: schema={schema_name}, username={username}, stored_user={tenant.admin_username}, stored_pass={tenant.admin_password}")
        if username == tenant.admin_username and password == tenant.admin_password:
            request.session['school_admin_authenticated'] = True
            request.session['school_admin_schema'] = tenant.schema_name
            request.session.save()  # Force session save
            print("[DEBUG] Login successful, session set, redirecting to dashboard")
            print(f"[DEBUG] Session keys after save: {list(request.session.keys())}")
            return redirect(f'/portal/{tenant.schema_name}/')
        print("[DEBUG] Invalid credentials")
        return render(request, 'tenant/login.html', {'tenant': tenant, 'error': 'Invalid credentials'})
    return render(request, 'tenant/login.html', {'tenant': tenant})"""

if old_login in urls_content:
    urls_content = urls_content.replace(old_login, new_login)
    print("✅ Patched login to force session save")
else:
    print("⚠️ Could not patch login (function format changed)")

# Also clean up dashboard debug to avoid spam
old_dash = """def school_dashboard(request, schema_name):
    tenant = get_school_tenant(schema_name)
    print(f"[DEBUG] Dashboard: schema={schema_name}, tenant={tenant}, session_auth={request.session.get('school_admin_authenticated')}, session_schema={request.session.get('school_admin_schema')}")
    if not tenant:
        print("[DEBUG] Tenant is None, redirecting to home")
        return redirect('/')
    if not request.session.get('school_admin_authenticated'):
        print("[DEBUG] Not authenticated, redirecting to login")
        return redirect(f'/portal/{tenant.schema_name}/login/')
    print("[DEBUG] Rendering dashboard")
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None})"""

new_dash = """def school_dashboard(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return redirect('/')
    if not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/')
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None})"""

if old_dash in urls_content:
    urls_content = urls_content.replace(old_dash, new_dash)
    print("✅ Cleaned dashboard debug")

with open(PUBLIC_URLS, "w") as f:
    f.write(urls_content)

print("\n✅ All fixes applied. Now RESTART the server:\n   python manage.py runserver\n")
