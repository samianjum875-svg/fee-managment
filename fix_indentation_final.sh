#!/bin/bash

# fix_indentation_final.sh – corrects indentation of fee_receipt in views.py
# Run once from project root: ./fix_indentation_final.sh

set -e

cd ~/axis_school_sys

# Backup current views.py
cp axis_saas/views.py axis_saas/views.py.backup_indent

python3 << 'EOF'
import re

file_path = "axis_saas/views.py"
with open(file_path, "r") as f:
    lines = f.readlines()

new_lines = []
i = 0
in_fee_receipt = False
while i < len(lines):
    line = lines[i]
    # Detect start of fee_receipt function
    if line.strip().startswith("def fee_receipt("):
        new_lines.append(line)  # keep the def line as is
        i += 1
        # Now we need to indent the following lines until the next function definition (def)
        # The current line after def is "tenant = get_tenant..." which has no indentation.
        # We will add 4 spaces to each line until we hit a line that starts with "def " (next function)
        while i < len(lines) and not lines[i].strip().startswith("def "):
            # If the line is empty, keep it empty (no indentation needed)
            if lines[i].strip() == "":
                new_lines.append("\n")
            else:
                # Add 4 spaces at the beginning
                new_lines.append("    " + lines[i])
            i += 1
        # Now we are at the next function definition (def defaulters) – will be added in the next iteration
        continue
    else:
        new_lines.append(line)
        i += 1

with open(file_path, "w") as f:
    f.writelines(new_lines)

print("✅ Indentation of fee_receipt fixed.")
EOF

echo ""
echo "🚀 Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
