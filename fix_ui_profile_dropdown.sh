#!/bin/bash

# fix_ui_profile_dropdown.sh - Improves dark theme contrast and adds profile dropdown
# Run from: ~/axis_school_sys

set -e

BASE_FILE="templates/tenant/base.html"

if [ ! -f "$BASE_FILE" ]; then
    echo "ERROR: $BASE_FILE not found. Are you in the project root?"
    exit 1
fi

# Backup
cp "$BASE_FILE" "${BASE_FILE}.bak_ui"
echo "✅ Backup created."

echo "✍️  Updating $BASE_FILE with dark theme improvements and profile dropdown..."

python3 << 'PYTHON_SCRIPT'
import re

base_file = "templates/tenant/base.html"

with open(base_file, "r") as f:
    content = f.read()

# 1. Improve dark theme variables for better contrast
old_dark_root = """        [data-theme="dark"] {
            --bg: #0f172a;
            --surface: rgba(30, 41, 59, 0.9);
            --surface-alt: rgba(51, 65, 85, 0.8);
            --text: #f1f5f9;
            --muted: #94a3b8;
            --primary: #60a5fa;
            --primary-dark: #3b82f6;
            --danger: #f87171;
            --border: rgba(255, 255, 255, 0.1);
        }"""

new_dark_root = """        [data-theme="dark"] {
            --bg: #0f172a;
            --surface: rgba(30, 41, 59, 0.95);
            --surface-alt: rgba(51, 65, 85, 0.9);
            --text: #f1f5f9;
            --muted: #cbd5e1;
            --primary: #60a5fa;
            --primary-dark: #3b82f6;
            --danger: #f87171;
            --border: rgba(255, 255, 255, 0.15);
        }"""

content = content.replace(old_dark_root, new_dark_root)

# 2. Locate the sidebar-footer section and replace with profile dropdown
# Find the sidebar-footer div
footer_start = content.find('<div class="sidebar-footer">')
if footer_start == -1:
    print("❌ Could not find sidebar-footer. Exiting.")
    exit(1)

# Find the end of sidebar-footer (matching </div>)
# We'll find the next closing div after footer_start that corresponds to the sidebar-footer
footer_end = content.find('</div>', footer_start)
# But we need to ensure we get the correct closing div. The sidebar-footer contains two buttons.
# We'll replace everything from footer_start until the </div> that closes it.
# Simpler: locate the line with sidebar-footer and then find the next </div> after that.
# However, there might be nested divs? In the given base.html, sidebar-footer contains two buttons and no nested divs.
# So we can safely take until the next </div>.
if footer_end == -1:
    print("❌ Could not find closing tag for sidebar-footer.")
    exit(1)

# New profile dropdown HTML
profile_dropdown = '''<div class="sidebar-footer">
    <div class="profile-dropdown">
        <button class="profile-btn" id="profileBtn">
            <div class="profile-avatar">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M5.121 17.804A13.937 13.937 0 0112 16c2.5 0 4.847.655 6.879 1.804M15 10a3 3 0 11-6 0 3 3 0 016 0zm6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
            </div>
            <span class="profile-name">Admin</span>
            <svg class="dropdown-arrow" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M6 9l6 6 6-6"/>
            </svg>
        </button>
        <div class="dropdown-menu" id="profileDropdown">
            <button onclick="toggleTheme()" class="dropdown-item">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"/></svg>
                <span>Theme</span>
            </button>
            <a href="{% url 'fee_settings' schema_name=tenant.schema_name %}" class="dropdown-item">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
                <span>Settings</span>
            </a>
            <a href="{% url 'tenant_logout' schema_name=tenant.schema_name %}" class="dropdown-item">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15M12 9l-3 3m0 0l3 3m-3-3h12.75"/></svg>
                <span>Logout</span>
            </a>
        </div>
    </div>
</div>'''

# Replace the old footer content
content = content[:footer_start] + profile_dropdown + content[footer_end+6:]  # +6 to skip the closing </div>

# 3. Remove the existing "Settings" nav item from sidebar-nav (gear icon)
# Find the nav-item for fee_settings and remove it
# We'll search for the line containing 'fee_settings' in the nav items
nav_start = content.find('<nav class="sidebar-nav">')
nav_end = content.find('</nav>', nav_start)
if nav_start != -1 and nav_end != -1:
    nav_section = content[nav_start:nav_end]
    # Remove the line with fee_settings
    # It looks like: <a href="{% url 'fee_settings' ... %}" class="nav-item"> ... </a>
    # We'll use regex to remove that whole <a> tag
    import re
    pattern = r'<a href="{% url \'fee_settings\'[^>]+>.*?</a>'
    new_nav_section = re.sub(pattern, '', nav_section, flags=re.DOTALL)
    # Also remove any extra whitespace lines
    new_nav_section = re.sub(r'\n\s*\n', '\n', new_nav_section)
    content = content[:nav_start] + new_nav_section + content[nav_end:]

# 4. Add CSS for profile dropdown and ensure sidebar height doesn't cause issues
# Insert CSS before the closing </style> tag (in the head)
style_end = content.find('</style>')
if style_end != -1:
    dropdown_css = '''
        /* Profile Dropdown */
        .profile-dropdown {
            position: relative;
        }
        .profile-btn {
            display: flex;
            align-items: center;
            gap: 8px;
            width: 100%;
            background: var(--surface-alt);
            border: 1px solid var(--border);
            border-radius: 2rem;
            padding: 0.5rem 0.75rem;
            cursor: pointer;
            color: var(--text);
            font-weight: 500;
            transition: var(--transition);
        }
        .profile-btn:hover {
            background: var(--surface);
        }
        .profile-avatar svg {
            stroke: var(--primary);
        }
        .profile-name {
            flex: 1;
            text-align: left;
            font-size: 0.85rem;
        }
        .dropdown-arrow {
            transition: transform 0.2s;
        }
        .dropdown-menu {
            position: absolute;
            bottom: 100%;
            left: 0;
            right: 0;
            margin-bottom: 0.5rem;
            background: var(--surface);
            backdrop-filter: blur(12px);
            border: 1px solid var(--border);
            border-radius: 1rem;
            padding: 0.5rem;
            display: none;
            z-index: 100;
            box-shadow: var(--shadow);
        }
        .dropdown-menu.show {
            display: block;
        }
        .dropdown-item {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.5rem 0.75rem;
            border-radius: 0.75rem;
            color: var(--text);
            text-decoration: none;
            font-size: 0.85rem;
            transition: var(--transition);
            cursor: pointer;
            width: 100%;
            background: none;
            border: none;
            font-family: inherit;
        }
        .dropdown-item:hover {
            background: var(--surface-alt);
            color: var(--primary);
        }
        .dropdown-item svg {
            stroke: currentColor;
        }
'''
    content = content[:style_end] + dropdown_css + content[style_end:]

# 5. Add JavaScript for dropdown toggle (replace the existing toggleTheme function? Keep it, add new)
# Find the </body> tag and insert script before it
body_end = content.rfind('</body>')
if body_end != -1:
    dropdown_js = '''
    <script>
        // Profile dropdown functionality
        const profileBtn = document.getElementById('profileBtn');
        const profileDropdown = document.getElementById('profileDropdown');
        if (profileBtn && profileDropdown) {
            profileBtn.addEventListener('click', function(e) {
                e.stopPropagation();
                profileDropdown.classList.toggle('show');
            });
            // Close dropdown when clicking outside
            document.addEventListener('click', function(e) {
                if (!profileBtn.contains(e.target) && !profileDropdown.contains(e.target)) {
                    profileDropdown.classList.remove('show');
                }
            });
            // Prevent dropdown from closing when clicking inside
            profileDropdown.addEventListener('click', function(e) {
                e.stopPropagation();
            });
        }
    </script>
'''
    # Insert before </body>
    content = content[:body_end] + dropdown_js + content[body_end:]

# Write back
with open(base_file, "w") as f:
    f.write(content)

print("✅ base.html updated successfully.")
PYTHON_SCRIPT

echo ""
echo "🎉 UI improvements and profile dropdown added!"
echo "Restart your Django server to see the changes:"
echo "   source venv/bin/activate"
echo "   python3 manage.py runserver"
echo ""
echo "Changes:"
echo "  - Dark theme contrast improved"
echo "  - Profile dropdown at bottom of sidebar (avatar, admin name)"
echo "  - Dropdown contains: Theme toggle, Settings, Logout"
echo "  - The separate Settings nav item and footer buttons removed"
