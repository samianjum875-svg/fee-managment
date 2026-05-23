#!/bin/bash

# fix_receipt.sh – fixes lazy loading in fee_receipt view
# Run once from project root: ./fix_receipt.sh

set -e

cd ~/axis_school_sys

# Backup current views.py
cp axis_saas/views.py axis_saas/views.py.backup_receipt

python3 << 'EOF'
import re

file_path = "axis_saas/views.py"
with open(file_path, "r") as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    # Look for the fee_receipt function
    if "def fee_receipt(request, schema_name, receipt_id):" in line:
        new_lines.append(line)  # keep the definition line
        i += 1
        # Read until we find the 'return' line, but we want to replace the function body
        # We'll collect lines until we see the return, then replace with our version
        func_lines = [line]  # we already added definition, we need to collect body
        # But easier: we can just locate the existing 'payment = get_object_or_404...' line and replace the block.
        # Since the function is small, we will rebuild it completely.
        # Let's find the indentation level from the definition line.
        indent_match = re.match(r'^(\s*)', line)
        indent = indent_match.group(1) if indent_match else '    '
        # Build new function body
        new_func = [
            f"{indent}tenant = get_tenant(request, schema_name)\n",
            f"{indent}with schema_context(schema_name):\n",
            f"{indent}    payment = get_object_or_404(PaymentTransaction.objects.select_related('student'), id=receipt_id)\n",
            f"{indent}    fee_records = list(payment.fee_records.all())\n",
            f"{indent}    context = {{\n",
            f"{indent}        'tenant': tenant,\n",
            f"{indent}        'payment': payment,\n",
            f"{indent}        'fee_records': fee_records,\n",
            f"{indent}        'logo_url': tenant.school_logo.url if tenant.school_logo else None,\n",
            f"{indent}    }}\n",
            f"{indent}return render(request, 'tenant/receipt.html', context)\n"
        ]
        # Skip the old function body until we hit the next function definition or EOF
        while i < len(lines) and not lines[i].strip().startswith('def '):
            i += 1
        # Insert the new function body
        new_lines.extend(new_func)
        continue
    else:
        new_lines.append(line)
    i += 1

with open(file_path, "w") as f:
    f.writelines(new_lines)

print("✅ fee_receipt view fixed – uses select_related and pre‑fetches fee_records.")
EOF

echo ""
echo "🚀 Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
