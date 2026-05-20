import re

file_path = "axis_saas/public_urls.py"

with open(file_path, "r") as f:
    content = f.read()

# Replace school_dashboard with debug version
old_dashboard = """def school_dashboard(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant or not request.session.get('school_admin_authenticated'):
        return redirect(f'/portal/{tenant.schema_name}/login/' if tenant else '/')
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': tenant.school_logo.url if tenant.school_logo else None})"""

new_dashboard = """def school_dashboard(request, schema_name):
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

if old_dashboard in content:
    content = content.replace(old_dashboard, new_dashboard)
    print("✅ Patched school_dashboard with debug prints")
else:
    print("⚠️ Could not find old dashboard function")

# Also patch school_login to print debug info
old_login = """def school_login(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School not found')
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        if username == tenant.admin_username and password == tenant.admin_password:
            request.session['school_admin_authenticated'] = True
            request.session['school_admin_schema'] = tenant.schema_name
            return redirect(f'/portal/{tenant.schema_name}/')
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
            print("[DEBUG] Login successful, session set, redirecting to dashboard")
            return redirect(f'/portal/{tenant.schema_name}/')
        print("[DEBUG] Invalid credentials")
        return render(request, 'tenant/login.html', {'tenant': tenant, 'error': 'Invalid credentials'})
    return render(request, 'tenant/login.html', {'tenant': tenant})"""

if old_login in content:
    content = content.replace(old_login, new_login)
    print("✅ Patched school_login with debug prints")
else:
    print("⚠️ Could not find old login function")

with open(file_path, "w") as f:
    f.write(content)

print("Debug patch applied. Restart server and watch terminal output.")
