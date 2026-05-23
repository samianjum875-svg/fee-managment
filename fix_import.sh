#!/bin/bash
# =============================================================================
# AXIS School System – Fix missing grade_income_api import
# =============================================================================
# This script adds 'grade_income_api' to the import statements in public_urls.py
# =============================================================================

set -e

PROJECT_ROOT="$(pwd)"
TARGET="$PROJECT_ROOT/axis_saas/public_urls.py"

if [ ! -f "$TARGET" ]; then
    echo "❌ ERROR: $TARGET not found."
    echo "   Please run this script from the directory that contains 'manage.py'."
    exit 1
fi

# Backup
cp "$TARGET" "$TARGET.bak"
echo "✅ Backup created: $TARGET.bak"

# Use Python to safely modify the import lines
python3 << 'PYTHON_FIX'
import re

file_path = "axis_saas/public_urls.py"

with open(file_path, 'r') as f:
    content = f.read()

# Check if grade_income_api is already imported
if 'grade_income_api' not in content:
    # Find the last import line that starts with 'from .views import'
    # We'll add it to the last such line (or create a new line)
    lines = content.split('\n')
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.strip().startswith('from .views import'):
            last_import_idx = i

    if last_import_idx != -1:
        # Get the line
        import_line = lines[last_import_idx]
        # If it ends with a backslash continuation? No, it's a plain line.
        # We'll add grade_income_api to the end, ensuring commas.
        if import_line.rstrip().endswith(','):
            new_line = import_line + ' grade_income_api'
        else:
            new_line = import_line + ', grade_income_api'
        lines[last_import_idx] = new_line
        content = '\n'.join(lines)
    else:
        # No import line found? Add one at the top after other imports.
        # Insert after the last 'from .views import' line? Actually just add a new line after existing imports.
        # We'll add it after the last import of any kind.
        import re
        # Find position to insert: after the last 'from .views import' or after 'from .models import'?
        # Simpler: add at the end of the block of import statements.
        # We'll insert just before the 'def saas_homepage' line.
        pattern = r'(from \.views import .*?)\n(?!from \.views)'
        # Not perfect, but we'll do a direct insert.
        insertion = "\nfrom .views import grade_income_api\n"
        # Find a safe place: after the last line that starts with 'from .views'
        last_view_import = max([m.end() for m in re.finditer(r'^from \.views import .*$', content, re.MULTILINE)])
        content = content[:last_view_import] + insertion + content[last_view_import:]
        # But careful with newlines, just do simple replace after last import.
        # Actually we'll just use the first approach: if no import line found, we create a new line at the top.
        # However that case is unlikely. We'll keep it simple: add after the existing imports block.
        # Let's find the line after the last import and insert.
        # Use a more robust method:
        # Find the last line that starts with 'from .views'
        import re
        matches = list(re.finditer(r'^from \.views import .*$', content, re.MULTILINE))
        if matches:
            last_match = matches[-1]
            insert_pos = last_match.end()
            content = content[:insert_pos] + "\nfrom .views import grade_income_api" + content[insert_pos:]
        else:
            # fallback: add at top
            content = "from .views import grade_income_api\n" + content

# Write back
with open(file_path, 'w') as f:
    f.write(content)

print("✅ Import for grade_income_api added successfully.")
PYTHON_FIX

echo ""
echo "🎉 Done! Now you can start the server:"
echo "   python3 manage.py runserver"
echo ""
echo "If anything goes wrong, restore from backup: cp $TARGET.bak $TARGET"
