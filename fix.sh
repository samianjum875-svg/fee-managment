#!/bin/bash
# =============================================================================
# AXIS School System – One‑Click Syntax Error Fixer
# =============================================================================
# This script repairs:
#   - Missing import of grade_income_api
#   - The broken line with two path() calls on one line
# =============================================================================

set -e  # stop on any error

PROJECT_ROOT="$(pwd)"
TARGET="$PROJECT_ROOT/axis_saas/public_urls.py"

if [ ! -f "$TARGET" ]; then
    echo "❌ ERROR: $TARGET not found."
    echo "   Please run this script from the directory that contains 'manage.py'."
    exit 1
fi

# Backup the original file
cp "$TARGET" "$TARGET.bak"
echo "✅ Backup created: $TARGET.bak"

# Use Python to apply the fixes precisely
python3 << 'PYTHON_FIX'
import re

file_path = "axis_saas/public_urls.py"

with open(file_path, 'r') as f:
    content = f.read()

# 1. Add grade_income_api to the import list if not already present
if 'grade_income_api' not in content:
    # Look for the line that imports the views
    # Example: from .views import dashboard, student_list, ... student_payments_api, debug_payments_api
    import_pattern = r'(from \.views import .*?)(\n)'
    def add_import(match):
        imports = match.group(1)
        # Add grade_income_api if not already there
        if 'grade_income_api' not in imports:
            # insert before the last item or at the end
            if imports.endswith(','):
                new_imports = imports + ' grade_income_api,'
            else:
                new_imports = imports + ', grade_income_api'
            return new_imports + match.group(2)
        return match.group(0)
    content = re.sub(import_pattern, add_import, content, count=1)

# 2. Fix the broken line with two path() calls
# Original broken line:
# path('portal/<slug:schema_name>/api/student/<int:student_id>/payments/', student_payments_api_view, name='student_payments_api'),    path(\'portal/<slug:schema_name>/api/grade-income/\', grade_income_api, name=\'grade_income_api\'),
# We need to replace it with two proper lines, each with 4 spaces indentation.
broken_line_pattern = r"path\('portal/<slug:schema_name>/api/student/<int:student_id>/payments/', student_payments_api_view, name='student_payments_api'\),\s+path\\(\\'portal/<slug:schema_name>/api/grade-income/\\', grade_income_api, name=\\'grade_income_api\\'\\),"

replacement = (
    "    path('portal/<slug:schema_name>/api/student/<int:student_id>/payments/', student_payments_api_view, name='student_payments_api'),\n"
    "    path('portal/<slug:schema_name>/api/grade-income/', grade_income_api, name='grade_income_api'),"
)

content = re.sub(broken_line_pattern, replacement, content)

# Also handle if the line appears without the escaped quotes (just in case)
# But the error shows escaped quotes, so above should match.
# If not, try a simpler replace for safety.
if "path(\\'portal/<slug:schema_name>/api/grade-income/\\'" in content:
    content = content.replace(
        "path('portal/<slug:schema_name>/api/student/<int:student_id>/payments/', student_payments_api_view, name='student_payments_api'),    path(\\'portal/<slug:schema_name>/api/grade-income/\\', grade_income_api, name=\\'grade_income_api\\'),",
        "    path('portal/<slug:schema_name>/api/student/<int:student_id>/payments/', student_payments_api_view, name='student_payments_api'),\n    path('portal/<slug:schema_name>/api/grade-income/', grade_income_api, name='grade_income_api'),"
    )

# Write back
with open(file_path, 'w') as f:
    f.write(content)

print("✅ public_urls.py has been fixed.")
PYTHON_FIX

echo ""
echo "🎉 Done! You can now start the server:"
echo "   python3 manage.py runserver"
echo ""
echo "If you ever need to revert, the original file is saved as public_urls.py.bak"
