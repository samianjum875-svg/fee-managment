import os
import re

# 1. Create a new middleware that protects session operations
MIDDLEWARE_CODE = '''
class SafeSessionMiddleware:
    """Ensures session save always uses public schema."""
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        # After response is generated, before sending, ensure session save uses public schema
        if hasattr(request, 'session') and request.session.modified:
            from django.db import connection
            original_schema = connection.schema_name
            try:
                connection.set_schema('public')
                request.session.save()
            finally:
                connection.set_schema(original_schema)
        return response
'''

# Add the middleware code to a new file
with open("axis_saas/middleware_session.py", "w") as f:
    f.write(MIDDLEWARE_CODE)
print("✅ Created axis_saas/middleware_session.py")

# 2. Update settings.py to import this middleware and add to MIDDLEWARE
SETTINGS_FILE = "axis_saas/settings.py"
with open(SETTINGS_FILE, "r") as f:
    content = f.read()

# Add import at top if not present
if "from axis_saas.middleware_session import SafeSessionMiddleware" not in content:
    content = content.replace(
        "from django.middleware.clickjacking import XFrameOptionsMiddleware",
        "from django.middleware.clickjacking import XFrameOptionsMiddleware\nfrom axis_saas.middleware_session import SafeSessionMiddleware"
    )

# Insert SafeSessionMiddleware right after SessionMiddleware
if "SafeSessionMiddleware" not in content:
    # Find SessionMiddleware line and add after it
    content = re.sub(
        r"(django\.contrib\.sessions\.middleware\.SessionMiddleware',\n)",
        r"\1    'axis_saas.middleware_session.SafeSessionMiddleware',\n",
        content
    )
    print("✅ Added SafeSessionMiddleware after SessionMiddleware")

# 3. Turn off SESSION_SAVE_EVERY_REQUEST to reduce writes
if "SESSION_SAVE_EVERY_REQUEST = True" in content:
    content = content.replace("SESSION_SAVE_EVERY_REQUEST = True", "SESSION_SAVE_EVERY_REQUEST = False")
    print("✅ Set SESSION_SAVE_EVERY_REQUEST = False")

with open(SETTINGS_FILE, "w") as f:
    f.write(content)

print("\n✅ Fix applied. Now restart server:")
print("   python manage.py runserver")
