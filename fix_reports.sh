#!/bin/bash

# fix_reports.sh – corrects lazy evaluation in reports view
# Run once from project root: ./fix_reports.sh

set -e

cd ~/axis_school_sys

# Backup current views.py
cp axis_saas/views.py axis_saas/views.py.backup_reports

python3 << 'EOF'
import re

file_path = "axis_saas/views.py"
with open(file_path, "r") as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    
    # Remove the problematic line that converts payments_qs to a list
    if "payments_qs = list(payments_qs)  # force evaluation inside schema context" in line:
        i += 1
        continue
    
    new_lines.append(line)
    
    # After the line that sets payments = payments_qs.order_by(...), add a list conversion
    if "payments = payments_qs.order_by('-payment_date')" in line:
        indent = re.match(r'^(\s*)', line).group(1)
        # Add the conversion on the next line (inside the with block)
        new_lines.append(f"{indent}payments = list(payments)  # force evaluation inside schema context\n")
    
    i += 1

with open(file_path, "w") as f:
    f.writelines(new_lines)

print("✅ views.py repaired – reports view now evaluates payments list correctly.")
EOF

echo ""
echo "🚀 Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
