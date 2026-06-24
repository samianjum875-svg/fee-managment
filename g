#!/usr/bin/env python3
"""
AXIS Template Feature Patcher
- Adds a custom template filter 'has_feature' to fee_extras.py
- Replaces all occurrences of tenant.is_feature_enabled('...') with tenant|has_feature:'...'
- Scans all templates for similar patterns
Run: python3 fix_template_features.py
"""

import os
import re
import glob

def main():
    # 1. Add filter to fee_extras.py
    extras_path = "axis_saas/templatetags/fee_extras.py"
    if os.path.exists(extras_path):
        with open(extras_path, "r") as f:
            content = f.read()
        if "def has_feature" not in content:
            # Add new filter after existing ones
            new_filter = """
@register.filter
def has_feature(tenant, feature_name):
    \"\"\"Return True if tenant has the given feature enabled.\"\"\"
    return tenant.is_feature_enabled(feature_name)
"""
            # Insert before the last line or at the end
            content = content.rstrip() + new_filter + "\n"
            with open(extras_path, "w") as f:
                f.write(content)
            print("✅ Added 'has_feature' filter to fee_extras.py")
        else:
            print("ℹ️ 'has_feature' filter already exists.")
    else:
        print("❌ fee_extras.py not found! Skipping.")

    # 2. Fix templates: base.html and any other tenant templates
    template_dir = "templates/tenant"
    if not os.path.exists(template_dir):
        print("❌ Templates directory not found!")
        return

    # Find all .html files in tenant templates
    html_files = glob.glob(os.path.join(template_dir, "*.html"))
    for file_path in html_files:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Check if the file uses the problematic pattern
        if "tenant.is_feature_enabled(" in content:
            # Replace pattern: tenant.is_feature_enabled('...') -> tenant|has_feature:'...'
            # Also handle double quotes
            new_content = re.sub(
                r'tenant\.is_feature_enabled\(\s*[\'"]([^\'"]+)[\'"]\s*\)',
                r"tenant|has_feature:'\1'",
                content
            )
            # Also ensure the load tag is present
            if "{% load fee_extras %}" not in new_content:
                # Insert it after the extends tag or at the top
                lines = new_content.splitlines()
                if lines and lines[0].startswith("{% extends"):
                    # Insert after the extends line
                    lines.insert(1, "{% load fee_extras %}")
                else:
                    # Insert at the beginning
                    lines.insert(0, "{% load fee_extras %}")
                new_content = "\n".join(lines)

            if new_content != content:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(new_content)
                print(f"✅ Fixed {file_path}")
            else:
                print(f"ℹ️ No changes needed in {file_path}")
        else:
            # Still ensure load tag exists if any filter is used
            # Not strictly necessary, but good practice
            pass

    # 3. Also fix any other templates (like base.html is in templates/tenant)
    # Already covered.

    print("\n🎯 Patcher finished. Restart the server:")
    print("   python manage.py runserver")
    print("   Then visit a school portal – the sidebar should work.")

if __name__ == "__main__":
    main()
