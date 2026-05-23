#!/bin/bash

# fix_sidebar_final.sh - Fixes sidebar scroll and collapsed profile dropdown
# Run from: ~/axis_school_sys

set -e

BASE_FILE="templates/tenant/base.html"

if [ ! -f "$BASE_FILE" ]; then
    echo "ERROR: $BASE_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup
cp "$BASE_FILE" "${BASE_FILE}.bak_final"
echo "✅ Backup created."

echo "✍️  Updating $BASE_FILE with final sidebar scroll and dropdown fixes..."

python3 << 'PYTHON_SCRIPT'
import re

base_file = "templates/tenant/base.html"

with open(base_file, "r") as f:
    content = f.read()

# 1. Ensure sidebar has height: 100vh and display: flex, flex-direction: column
# Find the .sidebar rule and replace if needed
sidebar_rule = r'\.sidebar \{[\s\S]*?\n\}'
if re.search(sidebar_rule, content):
    new_sidebar = """.sidebar {
    width: 280px;
    background: var(--surface);
    backdrop-filter: blur(12px);
    border-right: 1px solid var(--border);
    position: fixed;
    top: 0;
    bottom: 0;
    left: 0;
    display: flex;
    flex-direction: column;
    height: 100vh;
    transition: var(--transition);
    z-index: 50;
    box-shadow: var(--shadow);
}"""
    content = re.sub(sidebar_rule, new_sidebar, content, count=1)

# 2. Ensure .sidebar-nav has flex:1 and overflow-y: auto
sidebar_nav_rule = r'\.sidebar-nav \{[\s\S]*?\n\}'
if re.search(sidebar_nav_rule, content):
    new_sidebar_nav = """.sidebar-nav {
    flex: 1;
    padding: 1rem 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    overflow-y: auto;
}"""
    content = re.sub(sidebar_nav_rule, new_sidebar_nav, content, count=1)

# 3. Ensure .sidebar-footer is flex-shrink: 0
sidebar_footer_rule = r'\.sidebar-footer \{[\s\S]*?\n\}'
if re.search(sidebar_footer_rule, content):
    new_sidebar_footer = """.sidebar-footer {
    padding: 1rem 1.25rem;
    border-top: 1px solid var(--border);
    flex-shrink: 0;
}"""
    content = re.sub(sidebar_footer_rule, new_sidebar_footer, content, count=1)

# 4. Add collapsed dropdown positioning (open to the right when collapsed)
# Find the style tag end and insert CSS for collapsed dropdown
collapsed_dropdown_css = """
        /* When sidebar is collapsed, dropdown opens to the right */
        .sidebar.collapsed .profile-dropdown {
            position: static;
        }
        .sidebar.collapsed .dropdown-menu {
            position: fixed;
            left: calc(80px + 0.5rem);
            bottom: auto;
            top: auto;
            transform: translateY(-50%);
            margin-top: 0;
            width: 200px;
        }
        /* Adjust for small screens */
        @media (max-width: 768px) {
            .sidebar.collapsed .dropdown-menu {
                left: 80px;
            }
        }
"""

# Insert before </style>
style_end = content.find('</style>')
if style_end != -1:
    # Check if already present to avoid duplication
    if '.sidebar.collapsed .dropdown-menu' not in content:
        content = content[:style_end] + collapsed_dropdown_css + content[style_end:]

# 5. Update JavaScript to handle dropdown repositioning when collapsing
# We need to close dropdown when collapsing to avoid positioning issues
# Find the toggleSidebar function and add code to close dropdown
old_toggle = '''        function toggleSidebar() {
            sidebar.classList.toggle('collapsed');
            const isCollapsed = sidebar.classList.contains('collapsed');
            localStorage.setItem('sidebarCollapsed', isCollapsed);
            const svg = toggleBtn.querySelector('svg');
            if (isCollapsed) {
                svg.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>';
                // Update profile button for collapsed state
                const profileBtn = document.getElementById('profileBtn');
                if (profileBtn) {
                    const nameSpan = profileBtn.querySelector('.profile-name');
                    const arrowSvg = profileBtn.querySelector('.dropdown-arrow');
                    if (nameSpan) nameSpan.style.display = 'none';
                    if (arrowSvg) arrowSvg.style.display = 'none';
                }
            } else {
                svg.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"/>';
                // Update profile button for expanded state
                const profileBtn = document.getElementById('profileBtn');
                if (profileBtn) {
                    const nameSpan = profileBtn.querySelector('.profile-name');
                    const arrowSvg = profileBtn.querySelector('.dropdown-arrow');
                    if (nameSpan) nameSpan.style.display = '';
                    if (arrowSvg) arrowSvg.style.display = '';
                }
            }
        }'''

new_toggle = '''        function toggleSidebar() {
            sidebar.classList.toggle('collapsed');
            const isCollapsed = sidebar.classList.contains('collapsed');
            localStorage.setItem('sidebarCollapsed', isCollapsed);
            const svg = toggleBtn.querySelector('svg');
            if (isCollapsed) {
                svg.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>';
                // Update profile button for collapsed state
                const profileBtn = document.getElementById('profileBtn');
                if (profileBtn) {
                    const nameSpan = profileBtn.querySelector('.profile-name');
                    const arrowSvg = profileBtn.querySelector('.dropdown-arrow');
                    if (nameSpan) nameSpan.style.display = 'none';
                    if (arrowSvg) arrowSvg.style.display = 'none';
                }
                // Close dropdown when collapsing to avoid positioning issues
                const dropdown = document.getElementById('profileDropdown');
                if (dropdown) dropdown.classList.remove('show');
            } else {
                svg.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"/>';
                // Update profile button for expanded state
                const profileBtn = document.getElementById('profileBtn');
                if (profileBtn) {
                    const nameSpan = profileBtn.querySelector('.profile-name');
                    const arrowSvg = profileBtn.querySelector('.dropdown-arrow');
                    if (nameSpan) nameSpan.style.display = '';
                    if (arrowSvg) arrowSvg.style.display = '';
                }
            }
        }'''

if old_toggle in content:
    content = content.replace(old_toggle, new_toggle)
else:
    # Fallback pattern replacement
    pattern = r'function toggleSidebar\(\) \{[\s\S]*?\n\s+\}'
    def replacer(match):
        return new_toggle
    content = re.sub(pattern, replacer, content, count=1)

# 6. Also ensure initial state dropdown is closed if collapsed
init_script = '''        if (sidebar.classList.contains('collapsed')) {
            toggleBtn.querySelector('svg').innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>';
            const profileBtn = document.getElementById('profileBtn');
            if (profileBtn) {
                const nameSpan = profileBtn.querySelector('.profile-name');
                const arrowSvg = profileBtn.querySelector('.dropdown-arrow');
                if (nameSpan) nameSpan.style.display = 'none';
                if (arrowSvg) arrowSvg.style.display = 'none';
            }
        }'''

# Already present, no need to modify

# Write back
with open(base_file, "w") as f:
    f.write(content)

print("✅ base.html updated successfully.")
PYTHON_SCRIPT

echo ""
echo "🎉 Final fixes applied:"
echo "  - Sidebar now has fixed height and scrollable navigation"
echo "  - Profile dropdown stays at bottom"
echo "  - When sidebar collapsed, dropdown opens to the right (outside sidebar)"
echo "  - Dropdown closes automatically when collapsing sidebar"
echo ""
echo "Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
