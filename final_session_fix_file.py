import os
import re

SETTINGS_FILE = "axis_saas/settings.py"

with open(SETTINGS_FILE, "r") as f:
    content = f.read()

# 1. Change SESSION_ENGINE to file-based
if "SESSION_ENGINE" not in content:
    content = content.replace(
        "SESSION_SAVE_EVERY_REQUEST = False",
        "SESSION_ENGINE = 'django.contrib.sessions.backends.file'\nSESSION_SAVE_EVERY_REQUEST = False"
    )
else:
    content = re.sub(r"SESSION_ENGINE = .*", "SESSION_ENGINE = 'django.contrib.sessions.backends.file'", content)

# 2. Remove SafeSessionMiddleware if present
content = re.sub(r"from axis_saas.middleware_session import SafeSessionMiddleware\n", "", content)
content = re.sub(r"    'axis_saas.middleware_session.SafeSessionMiddleware',\n", "", content)

# 3. Ensure SESSION_FILE_PATH is set (optional)
if "SESSION_FILE_PATH" not in content:
    content += "\nSESSION_FILE_PATH = '/tmp/django_sessions/'\n"

# 4. Make sure session directory exists
os.makedirs('/tmp/django_sessions', exist_ok=True)

with open(SETTINGS_FILE, "w") as f:
    f.write(content)

print("✅ Changed SESSION_ENGINE to file-based")
print("✅ Removed SafeSessionMiddleware")
print("✅ Created /tmp/django_sessions directory")
print("\nNow restart server: python manage.py runserver")
