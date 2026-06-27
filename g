#!/usr/bin/env python3
"""
Patcher: Fix indentation error in axis_saas/views.py
- Line with 'template = 'mobile/fee_settings.html' ...' had wrong indentation.
- Adjusts it to match the surrounding context (same level as 'context =').
"""
import re
import os

def fix_fee_settings_indentation(views_path):
    """Read views.py, locate fee_settings function, fix template line indent."""
    if not os.path.exists(views_path):
        print(f"❌ File not found: {views_path}")
        return

    with open(views_path, 'r') as f:
        lines = f.readlines()

    # 1. Find the start of fee_settings function
    fee_start = None
    for i, line in enumerate(lines):
        if re.match(r'^def fee_settings\(', line):
            fee_start = i
            break

    if fee_start is None:
        print("❌ Could not find 'def fee_settings'")
        return

    # 2. Find the context line and the template line inside that function
    context_line_idx = None
    template_line_idx = None
    correct_indent = None

    for i in range(fee_start, len(lines)):
        line = lines[i]
        # Identify the line 'context = {...}'
        if 'context = {' in line and 'tenant' in line:
            context_line_idx = i
            # Count leading spaces
            correct_indent = len(line) - len(line.lstrip())
        # Identify the offending line
        if 'template = ' in line and "fee_settings.html" in line:
            template_line_idx = i

    if template_line_idx is None:
        print("❌ Could not find the template line")
        return

    if correct_indent is None:
        print("❌ Could not determine correct indentation from context line")
        return

    # 3. Fix the indentation
    old_line = lines[template_line_idx]
    new_line = ' ' * correct_indent + old_line.lstrip()

    if new_line == old_line:
        print("✅ Indentation already correct. No changes made.")
        return

    lines[template_line_idx] = new_line

    # 4. Write back
    with open(views_path, 'w') as f:
        f.writelines(lines)

    print(f"✅ Fixed indentation at line {template_line_idx+1} in {views_path}")


if __name__ == "__main__":
    # Path to your views.py (adjust if needed)
    VIEWS_PATH = "/home/sami/axis_school_sys/axis_saas/views.py"
    fix_fee_settings_indentation(VIEWS_PATH)
