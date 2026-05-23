#!/bin/bash

# fix_sidebar_scroll.sh - Fixes sidebar scroll and collapsed profile dropdown
# Run from: ~/axis_school_sys

set -e

BASE_FILE="templates/tenant/base.html"

if [ ! -f "$BASE_FILE" ]; then
    echo "ERROR: $BASE_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup
cp "$BASE_FILE" "${BASE_FILE}.bak_scroll"
echo "✅ Backup created."

echo "✍️  Updating $BASE_FILE with sidebar scroll and collapsed profile improvements..."

python3 << 'PYTHON_SCRIPT'
import re

base_file = "templates/tenant/base.html"

with open(base_file, "r") as f:
    content = f.read()

# 1. Update sidebar CSS to support scrolling
sidebar_css_pattern = r'(\.sidebar \{[\s\S]*?\})'
# We need to replace the .sidebar block with a version that has height: 100vh, display: flex, flex-direction: column
# Also add overflow handling for .sidebar-nav

new_sidebar_css = """.sidebar {
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

# Also add CSS for .sidebar-nav to be scrollable
sidebar_nav_rule = """.sidebar-nav {
    flex: 1;
    padding: 1rem 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    overflow-y: auto;
}"""

# And ensure .sidebar-footer stays at bottom
sidebar_footer_rule = """.sidebar-footer {
    padding: 1rem 1.25rem;
    border-top: 1px solid var(--border);
    flex-shrink: 0;
}"""

# Replace existing .sidebar CSS
content = re.sub(r'\.sidebar \{[\s\S]*?\n\}', new_sidebar_css, content, count=1)

# Replace .sidebar-nav if present, or add the overflow property
if '.sidebar-nav {' in content:
    content = re.sub(r'\.sidebar-nav \{[\s\S]*?\n\}', sidebar_nav_rule, content, count=1)
else:
    # Find </style> and insert before it
    style_end = content.find('</style>')
    if style_end != -1:
        content = content[:style_end] + sidebar_nav_rule + content[style_end:]

# Replace .sidebar-footer if present, else add
if '.sidebar-footer {' in content:
    content = re.sub(r'\.sidebar-footer \{[\s\S]*?\n\}', sidebar_footer_rule, content, count=1)
else:
    style_end = content.find('</style>')
    if style_end != -1:
        content = content[:style_end] + sidebar_footer_rule + content[style_end:]

# 2. Update JavaScript to handle profile button content when collapsing
# Find the toggleSidebar function and add logic to update profile button text/arrow
old_toggle = '''        function toggleSidebar() {
            sidebar.classList.toggle('collapsed');
            const isCollapsed = sidebar.classList.contains('collapsed');
            localStorage.setItem('sidebarCollapsed', isCollapsed);
            const svg = toggleBtn.querySelector('svg');
            if (isCollapsed) {
                svg.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>';
            } else {
                svg.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"/>';
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

# Also need to handle initial load – if sidebar is collapsed from localStorage, adjust profile button
# Find the section after toggleSidebar where we apply initial collapsed state
# We'll add an additional script block after the existing script to handle initial state
# Look for the line: if (sidebar.classList.contains('collapsed')) { ... }
# We'll append a new script after that to also set profile button based on initial collapsed state

# Replace the toggle function
if old_toggle in content:
    content = content.replace(old_toggle, new_toggle)
else:
    # Fallback: find the function body using regex
    pattern = r'function toggleSidebar\(\) \{[\s\S]*?\n\s+\}'
    def replacer(match):
        return new_toggle
    content = re.sub(pattern, replacer, content, count=1)

# Add initial profile button adjustment after the existing initialisation
# Find the place where we set sidebar.collapsed from localStorage and adjust logo
init_script = '''
        if (sidebar.classList.contains('collapsed')) {
            toggleBtn.querySelector('svg').innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>';
        }'''

# Replace with version that also adjusts profile button
new_init = '''
        if (sidebar.classList.contains('collapsed')) {
            toggleBtn.querySelector('svg').innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M13 5l7 7-7 7M5 5l7 7-7 7"/>';
            const profileBtn = document.getElementById('profileBtn');
            if (profileBtn) {
                const nameSpan = profileBtn.querySelector('.profile-name');
                const arrowSvg = profileBtn.querySelector('.dropdown-arrow');
                if (nameSpan) nameSpan.style.display = 'none';
                if (arrowSvg) arrowSvg.style.display = 'none';
            }
        }'''

content = content.replace(init_script, new_init)

# 3. Add CSS for collapsed profile button (hide name and arrow when sidebar.collapsed)
# Add to existing CSS near the .sidebar.collapsed rules
collapsed_profile_css = '''
        .sidebar.collapsed .profile-name,
        .sidebar.collapsed .dropdown-arrow {
            display: none;
        }
        .sidebar.collapsed .profile-btn {
            justify-content: center;
            padding: 0.5rem;
        }
        .sidebar.collapsed .profile-avatar {
            margin: 0;
        }'''

# Find where .sidebar.collapsed rules end (after last .sidebar.collapsed rule) and insert before closing </style>
style_end = content.find('</style>')
if style_end != -1:
    # Insert before </style>
    content = content[:style_end] + collapsed_profile_css + content[style_end:]

# Write back
with open(base_file, "w") as f:
    f.write(content)

print("✅ base.html updated successfully.")
PYTHON_SCRIPT

echo ""
echo "🎉 Sidebar scroll and profile dropdown in collapsed mode fixed!"
echo "Restart your Django server:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
