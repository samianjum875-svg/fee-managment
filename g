#!/usr/bin/env python3
import re
import os

PUBLIC_URLS_PATH = "axis_saas/public_urls.py"
VIEWS_PATH = "axis_saas/views.py"

def fix_public_urls():
    if not os.path.exists(PUBLIC_URLS_PATH):
        print(f"❌ {PUBLIC_URLS_PATH} not found")
        return

    with open(PUBLIC_URLS_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Add missing API names to the import line
    # The existing import line is very long; we'll insert the new names after an existing one.
    # We'll look for "gym_subscription_status_api" and add the new ones after it.
    new_imports = "gym_attendance_data_api, gym_eligible_customers_api, gym_search_customer_api, gym_export_attendance_api"
    if new_imports not in content:
        # Find the line that contains "gym_subscription_status_api"
        pattern = r'(from \.views import .*?gym_subscription_status_api)'
        replacement = r'\1, ' + new_imports
        content = re.sub(pattern, replacement, content, count=1)
        with open(PUBLIC_URLS_PATH, "w", encoding="utf-8") as f:
            f.write(content)
        print("✅ Updated import statement in public_urls.py")
    else:
        print("ℹ️ Imports already present")

def fix_views_duplicates():
    if not os.path.exists(VIEWS_PATH):
        print(f"❌ {VIEWS_PATH} not found")
        return
    with open(VIEWS_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    # Remove duplicate @csrf_exempt decorators
    content = re.sub(r"(@csrf_exempt\s*){2,}", "@csrf_exempt\n", content)
    with open(VIEWS_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print("✅ Cleaned duplicate decorators in views.py")

if __name__ == "__main__":
    fix_public_urls()
    fix_views_duplicates()
    print("\n🎉 Done. Restart the server: python3 manage.py runserver")
