#!/usr/bin/env python3
"""
Fix gym tenant login redirect - changes school_login to redirect to appropriate dashboard.
"""

import re
import os

PUBLIC_URLS = "axis_saas/public_urls.py"

def fix_login_redirect():
    with open(PUBLIC_URLS, "r") as f:
        content = f.read()

    # Check if the redirect is still hardcoded to 'dashboard'
    if "return redirect('dashboard', schema_name=tenant.schema_name)" not in content:
        print("Login redirect may already be fixed. Checking...")
        if "if tenant.tenant_type == 'gym'" in content:
            print("✅ Fix already applied.")
            return False

    # We need to replace the entire school_login function
    # Find the function and replace it with the fixed version
    function_pattern = r'def school_login\(request, schema_name\):.*?(?=\n\ndef |\n\Z)'
    
    match = re.search(function_pattern, content, re.DOTALL)
    if not match:
        print("Could not find school_login function")
        return False

    new_function = '''def school_login(request, schema_name):
    # Ensure tenant exists
    tenant = ensure_schoolclient(schema_name)
    if tenant is None:
        raise Http404(f"Tenant schema '{schema_name}' does not exist.")

    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        if username == tenant.admin_username and password == tenant.admin_password:
            request.session['school_admin_authenticated'] = True
            request.session['school_admin_schema'] = tenant.schema_name
            request.session['school_admin_username'] = username
            # Redirect to appropriate dashboard based on tenant_type
            if tenant.tenant_type == 'gym':
                return redirect('gym_dashboard', schema_name=tenant.schema_name)
            else:
                return redirect('dashboard', schema_name=tenant.schema_name)
        return render(request, 'tenant/login.html', {'tenant': tenant, 'error': 'Invalid credentials'})
    return render(request, 'tenant/login.html', {'tenant': tenant})'''

    new_content = content.replace(match.group(0), new_function)
    
    with open(PUBLIC_URLS, "w") as f:
        f.write(new_content)
    
    print("✅ Fixed login redirect: gym tenants now go to gym_dashboard")
    return True

def main():
    if not os.path.exists(PUBLIC_URLS):
        print(f"Error: {PUBLIC_URLS} not found")
        return

    fix_login_redirect()
    print("\n🎉 Fix applied! Restart your Django server:")
    print("   python3 manage.py runserver")
    print("Then try logging into the gym tenant again.")

if __name__ == "__main__":
    main()
