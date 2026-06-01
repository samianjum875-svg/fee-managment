#!/usr/bin/env python3
"""
Add missing gym views to import in public_urls.py.
Run: python3 fix_gym_imports.py
"""

import re
from pathlib import Path

PUBLIC_URLS = Path("axis_saas/public_urls.py")

def main():
    if not PUBLIC_URLS.exists():
        print("❌ public_urls.py not found")
        return

    with open(PUBLIC_URLS, "r") as f:
        content = f.read()

    # Find the line that starts with "from .views import"
    pattern = r'(from \.views import )(.*)'
    match = re.search(pattern, content)
    if not match:
        print("❌ Could not find import line")
        return

    prefix = match.group(1)
    existing_imports = match.group(2).strip()
    # Split existing imports (they may be separated by commas and spaces)
    import_list = [name.strip() for name in existing_imports.split(',') if name.strip()]

    # List of gym views that need to be imported (all that are used in public_urls.py)
    required_views = [
        'gym_dashboard', 'gym_customer_list', 'gym_customer_add', 'gym_customer_edit',
        'gym_customer_profile', 'gym_attendance', 'gym_payment', 'gym_reports', 'gym_settings'
    ]

    # Add missing ones
    for view in required_views:
        if view not in import_list:
            import_list.append(view)

    # Rebuild the import line
    new_import_line = prefix + ', '.join(sorted(import_list)) + '\n'

    # Replace the old line
    new_content = re.sub(pattern, new_import_line.rstrip(), content)

    # Backup
    backup = PUBLIC_URLS.with_suffix('.py.bak4')
    import shutil
    shutil.copy2(PUBLIC_URLS, backup)
    print(f"📁 Backup saved: {backup}")

    with open(PUBLIC_URLS, "w") as f:
        f.write(new_content)

    print("✅ Added missing gym views to import.")
    print("\n🎉 Now run: python3 manage.py runserver")

if __name__ == "__main__":
    main()
