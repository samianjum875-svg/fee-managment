import re

SETTINGS_FILE = "axis_saas/settings.py"

with open(SETTINGS_FILE, "r") as f:
    content = f.read()

# Remove the entire CrossTenantSessionIsolationMiddleware class and its usage
# Find from "# class CrossTenantSessionIsolationMiddleware" to the end of its methods
pattern = r'# class CrossTenantSessionIsolationMiddleware\(MiddlewareMixin\):.*?def process_response.*?return response'
content = re.sub(pattern, '', content, flags=re.DOTALL)

# Also remove any leftover blank lines and ensure MIDDLEWARE list doesn't have that middleware
# (already commented out, but clean up)
content = re.sub(r'#?\s*\'axis_saas\.settings\.CrossTenantSessionIsolationMiddleware\',\n', '', content)

# Ensure SESSION_COOKIE_PATH is set
if "SESSION_COOKIE_PATH" not in content:
    content += "\nSESSION_COOKIE_PATH = '/'\n"

# Write back
with open(SETTINGS_FILE, "w") as f:
    f.write(content)

print("✅ Removed broken CrossTenantSessionIsolationMiddleware")
print("✅ SESSION_COOKIE_PATH set to '/'")
print("\nNow restart server: python manage.py runserver")
