#!/usr/bin/env python3
"""
Fix collect_fee.html template: use server-side total_pending as base,
not DOM element that may be missing.
"""

import re

TEMPLATE_FILE = "templates/tenant/collect_fee.html"

def fix_template():
    with open(TEMPLATE_FILE, "r") as f:
        content = f.read()

    # Find the <script> block
    script_start = content.find("<script>")
    script_end = content.find("</script>", script_start)
    if script_start == -1 or script_end == -1:
        print("❌ Could not find <script> block in collect_fee.html")
        return

    script_content = content[script_start:script_end+9]  # include </script>

    # 1. Add basePending constant after the existing constants
    # We'll find a good insertion point: after "const studentId = {{ student.id }};"
    insert_after = "const studentId = {{ student.id }};"
    if insert_after in script_content:
        # Insert basePending after that line
        new_script = script_content.replace(
            insert_after,
            insert_after + "\nconst basePending = {{ total_pending|floatformat:2 }};"
        )
    else:
        print("⚠️ Could not find insertion point, adding at top of script")
        new_script = script_content.replace(
            "<script>",
            "<script>\nconst basePending = {{ total_pending|floatformat:2 }};"
        )

    # 2. Replace getBasePendingTotal function
    # We'll replace the entire function definition
    old_func = r"function getBasePendingTotal\(\) \{\s*const raw = totalPendingSpan \? totalPendingSpan\.innerText : '0';\s*return Number\(raw\) \|\| 0;\s*\}"
    new_func = "function getBasePendingTotal() { return basePending; }"
    new_script = re.sub(old_func, new_func, new_script, flags=re.DOTALL)

    # 3. Remove the line that defines totalPendingSpan if it's no longer needed
    # We can keep it but it's unused; but we can remove to avoid confusion.
    # We'll comment it out or remove.
    # We'll find "const totalPendingSpan = document.getElementById('totalPending');" and remove it.
    # But careful: there might be other uses? In this template, it's only used in getBasePendingTotal.
    # After replacement, it's not used. We can remove.
    new_script = re.sub(r"const totalPendingSpan = document\.getElementById\('totalPending'\);\s*", "", new_script)

    # Replace the old script block with the new one
    content = content[:script_start] + new_script + content[script_end+9:]

    with open(TEMPLATE_FILE, "w") as f:
        f.write(content)

    print("✅ Successfully patched collect_fee.html")
    print("   - Added basePending constant with server-side total_pending")
    print("   - getBasePendingTotal now returns basePending")
    print("   - Removed unused totalPendingSpan DOM lookup")

if __name__ == "__main__":
    fix_template()
