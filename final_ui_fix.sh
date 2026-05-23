#!/bin/bash

# final_ui_fix.sh - Fixes dropdown direction, collapsed positioning, and dark mode contrast
# Run from: ~/axis_school_sys

set -e

BASE_FILE="templates/tenant/base.html"

if [ ! -f "$BASE_FILE" ]; then
    echo "ERROR: $BASE_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup
cp "$BASE_FILE" "${BASE_FILE}.bak_final_ui"
echo "✅ Backup created."

echo "✍️  Updating $BASE_FILE..."

python3 << 'PYTHON_SCRIPT'
import re

base_file = "templates/tenant/base.html"

with open(base_file, "r") as f:
    content = f.read()

# 1. Change dropdown to open downward (instead of upward)
# Find .dropdown-menu rules and replace
old_dropdown_menu = r'\.dropdown-menu \{[\s\S]*?\n\}'
new_dropdown_menu = """.dropdown-menu {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    margin-top: 0.5rem;
    background: var(--surface);
    backdrop-filter: blur(12px);
    border: 1px solid var(--border);
    border-radius: 1rem;
    padding: 0.5rem;
    display: none;
    z-index: 100;
    box-shadow: var(--shadow);
}"""
content = re.sub(old_dropdown_menu, new_dropdown_menu, content, flags=re.DOTALL)

# 2. Update collapsed dropdown positioning (open to the right, aligned with button)
# Replace the collapsed dropdown CSS block
old_collapsed_dropdown = r'/\* When sidebar is collapsed, dropdown opens to the right \*/\n\s*\.sidebar\.collapsed \.profile-dropdown \{[\s\S]*?\n\}'
new_collapsed_dropdown = """        /* When sidebar is collapsed, dropdown opens to the right */
        .sidebar.collapsed .profile-dropdown {
            position: static;
        }
        .sidebar.collapsed .dropdown-menu {
            position: fixed;
            left: calc(80px + 0.5rem);
            top: auto;
            transform: none;
            margin-top: 0;
            width: 200px;
        }"""
# Replace the existing block (if found) or insert before </style>
if re.search(old_collapsed_dropdown, content, re.DOTALL):
    content = re.sub(old_collapsed_dropdown, new_collapsed_dropdown, content, flags=re.DOTALL)
else:
    # Insert before </style>
    style_end = content.find('</style>')
    if style_end != -1:
        content = content[:style_end] + new_collapsed_dropdown + content[style_end:]

# 3. Improve dark mode contrast for cards and tables
# Add additional dark mode overrides
dark_override = """
        /* Dark mode enhancements */
        [data-theme="dark"] .card,
        [data-theme="dark"] .filter-card,
        [data-theme="dark"] .table-card,
        [data-theme="dark"] .chart-card,
        [data-theme="dark"] .stat-card,
        [data-theme="dark"] .student-panel,
        [data-theme="dark"] .history-card {
            background: rgba(30, 41, 59, 0.98);
            border-color: rgba(255, 255, 255, 0.2);
        }
        [data-theme="dark"] .data-table th {
            background: rgba(51, 65, 85, 0.95);
            color: #e2e8f0;
        }
        [data-theme="dark"] .data-table td {
            border-bottom-color: rgba(255, 255, 255, 0.1);
        }
        [data-theme="dark"] .profile-btn {
            background: rgba(51, 65, 85, 0.9);
        }
"""
style_end = content.find('</style>')
if style_end != -1:
    # Avoid duplicate insertion
    if '[data-theme="dark"] .card' not in content:
        content = content[:style_end] + dark_override + content[style_end:]

# 4. Ensure sidebar-nav has overflow-y auto (already there, but ensure)
if 'overflow-y: auto' not in content:
    content = content.replace('.sidebar-nav {', '.sidebar-nav {\n    overflow-y: auto;')

# 5. Adjust main content min-height to prevent sidebar overflow
# Ensure .main-content has min-height: 100vh
if '.main-content {' in content:
    content = content.replace('.main-content {', '.main-content {\n    min-height: 100vh;')
else:
    main_rule = ".main-content {\n    flex: 1;\n    margin-left: 280px;\n    padding: 2rem 2rem;\n    transition: var(--transition);\n    min-height: 100vh;\n}"
    content = re.sub(r'\.main-content \{[\s\S]*?\n\}', main_rule, content, count=1)

# Write back
with open(base_file, "w") as f:
    f.write(content)

print("✅ base.html updated successfully.")
PYTHON_SCRIPT

echo ""
echo "🎉 Final UI fixes applied:"
echo "  - Profile dropdown now opens downward"
echo "  - Collapsed sidebar dropdown appears to the right"
echo "  - Dark mode contrast improved for cards/tables"
echo "  - Sidebar and main content heights optimised"
echo ""
echo "Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
