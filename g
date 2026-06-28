#!/usr/bin/env python3
import re, os

def file_read(p): ...
def file_write(p, c): ...

mobile_profile = 'templates/mobile/student_profile.html'
if os.path.exists(mobile_profile):
    content = file_read(mobile_profile)
    # Remove any existing voucher button if present (to avoid duplicates)
    # We'll insert a new one.
    # Find the .profile-actions div and insert before </div>
    pattern = r'(<div class="profile-actions">.*?)(</div>)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        button = '''
    <button class="btn-primary" onclick="openVoucherModal({{ student.id }}, '{{ tenant.schema_name }}')">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M4 4v16h16M8 12h8M12 8v8"/>
        </svg>
        Voucher
    </button>'''
        new_content = content[:match.start(1)] + match.group(1) + button + match.group(2)
        file_write(mobile_profile, new_content)
        print("✅ Added voucher button to mobile profile.")
    else:
        print("⚠️ Could not find .profile-actions; skipping.")
else:
    print("⚠️ File not found.")
