#!/usr/bin/env python3
"""
Fix gym customer form:
- Remove photo field
- Improve form layout (grid, better styling)
"""

import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.absolute()

def backup_file(filepath):
    """Create a backup of the file before modifying."""
    import shutil
    backup_dir = PROJECT_ROOT / "backups_gym_form"
    backup_dir.mkdir(exist_ok=True)
    backup_path = backup_dir / filepath.name
    shutil.copy2(filepath, backup_path)
    print(f"📁 Backed up: {filepath} -> {backup_path}")

def fix_forms():
    """Remove 'photo' from GymCustomerForm fields."""
    forms_path = PROJECT_ROOT / "axis_saas" / "forms.py"
    if not forms_path.exists():
        print("❌ forms.py not found")
        return False

    with open(forms_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Find the GymCustomerForm class and remove 'photo' from fields list
    # We look for the fields definition: fields = ['name', 'phone', ..., 'photo']
    pattern = r"(fields\s*=\s*\[)([^\]]*)(\])"
    def replacer(match):
        fields_str = match.group(2)
        # Split by commas, strip, remove 'photo'
        fields = [f.strip().strip("'\"") for f in fields_str.split(",")]
        if "photo" in fields:
            fields.remove("photo")
        new_fields_str = ", ".join([f"'{f}'" for f in fields])
        return f"{match.group(1)}{new_fields_str}{match.group(3)}"

    new_content = re.sub(pattern, replacer, content, flags=re.DOTALL)
    if new_content == content:
        print("⚠️ No changes made to forms.py (photo field already removed or not found)")
        return False

    backup_file(forms_path)
    with open(forms_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print("✅ Removed 'photo' field from GymCustomerForm")
    return True

def fix_template():
    """Replace gym_customer_form.html with a better layout."""
    template_path = PROJECT_ROOT / "templates" / "tenant" / "gym_customer_form.html"
    if not template_path.exists():
        print("❌ gym_customer_form.html not found")
        return False

    new_template = """{% extends 'tenant/base.html' %}
{% block title %}{% if customer %}Edit{% else %}Add{% endif %} Customer | {{ tenant.name }}{% endblock %}
{% block body %}
<div class="page-header">
    <div>
        <h1 class="page-title">{% if customer %}✏️ Edit Customer{% else %}➕ Add New Customer{% endif %}</h1>
        <p class="page-desc">{% if customer %}Update customer information{% else %}Enter customer details{% endif %}</p>
    </div>
    <a href="{% url 'gym_customer_list' schema_name=tenant.schema_name %}" class="btn-secondary">← Back to List</a>
</div>

<div class="form-card">
    <form method="post" enctype="multipart/form-data">
        {% csrf_token %}
        <div class="form-grid">
            {% for field in form %}
            <div class="form-field">
                <label>{{ field.label }}</label>
                {{ field }}
                {% if field.errors %}
                <div class="field-error">{{ field.errors|striptags }}</div>
                {% endif %}
                {% if field.help_text %}
                <div class="field-help">{{ field.help_text }}</div>
                {% endif %}
            </div>
            {% endfor %}
        </div>
        <div class="form-actions">
            <button type="submit" class="btn-primary">{% if customer %}Update{% else %}Save{% endif %} Customer</button>
            <a href="{% url 'gym_customer_list' schema_name=tenant.schema_name %}" class="btn-secondary">Cancel</a>
        </div>
    </form>
</div>

<style>
    .page-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 1.5rem;
        flex-wrap: wrap;
        gap: 1rem;
    }
    .page-title {
        font-size: 1.8rem;
        font-weight: 700;
        background: linear-gradient(135deg, var(--primary), var(--primary-dark));
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
    }
    .page-desc {
        color: var(--muted);
    }
    .btn-secondary {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.5rem 1rem;
        border-radius: 2rem;
        font-weight: 500;
        font-size: 0.85rem;
        text-decoration: none;
        background: var(--surface-alt);
        color: var(--text);
        border: 1px solid var(--border);
    }
    .form-card {
        background: var(--surface);
        border-radius: var(--radius);
        border: 1px solid var(--border);
        padding: 1.5rem;
        box-shadow: var(--shadow-sm);
    }
    .form-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
        gap: 1rem;
    }
    .form-field {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
    }
    .form-field label {
        font-weight: 600;
        font-size: 0.85rem;
        color: var(--text);
    }
    .form-field input,
    .form-field select,
    .form-field textarea {
        width: 100%;
        padding: 0.6rem 0.75rem;
        border-radius: 0.5rem;
        border: 1px solid var(--border);
        background: var(--surface-alt);
        color: var(--text);
        font-size: 0.9rem;
        transition: 0.2s;
    }
    .form-field input:focus,
    .form-field select:focus,
    .form-field textarea:focus {
        outline: none;
        border-color: var(--primary);
        box-shadow: 0 0 0 2px rgba(59,130,246,0.2);
    }
    .field-error {
        color: var(--danger);
        font-size: 0.7rem;
    }
    .field-help {
        color: var(--muted);
        font-size: 0.7rem;
    }
    .form-actions {
        display: flex;
        gap: 1rem;
        margin-top: 1.5rem;
        justify-content: flex-end;
    }
    .btn-primary {
        background: var(--primary);
        color: white;
        padding: 0.6rem 1.2rem;
        border-radius: 2rem;
        border: none;
        font-weight: 600;
        cursor: pointer;
        transition: 0.2s;
    }
    .btn-primary:hover {
        background: var(--primary-dark);
    }
</style>
{% endblock %}
"""
    backup_file(template_path)
    with open(template_path, "w", encoding="utf-8") as f:
        f.write(new_template)
    print("✅ Replaced gym_customer_form.html with improved layout")
    return True

def main():
    print("🔧 Fixing gym customer form (remove photo, improve UI)")
    fix_forms()
    fix_template()
    print("\n✨ Done! Restart your server. The photo field is removed, and the form has a clean grid layout.")

if __name__ == "__main__":
    main()
