# fix_template.py
import re
import os

FILE = "templates/tenant/collect_fee.html"

def fix_template():
    if not os.path.exists(FILE):
        print(f"❌ File not found: {FILE}")
        return

    with open(FILE, "r") as f:
        content = f.read()

    # Original broken line: {% url \'student_profile\' ... %}
    # Replace with correct syntax: {% url "student_profile" ... %}
    original = r"{% url \\'student_profile\\'"
    fixed = '{% url "student_profile"'

    if original in content:
        content = content.replace(original, fixed)
        with open(FILE, "w") as f:
            f.write(content)
        print("✅ Template fixed successfully!")
        print("   Restart server: python manage.py runserver")
    else:
        # Fallback: remove backslashes from all url tags
        # Use regex to replace \' with " inside {% url ... %}
        def repl(match):
            return match.group(0).replace("\\'", '"')
        new_content = re.sub(r"{% url .*? %}", repl, content)
        if new_content != content:
            with open(FILE, "w") as f:
                f.write(new_content)
            print("✅ Fixed using fallback method.")
            print("   Restart server: python manage.py runserver")
        else:
            print("ℹ️ No changes needed. File may already be correct.")
            print("   Try restarting server.")

if __name__ == "__main__":
    fix_template()
