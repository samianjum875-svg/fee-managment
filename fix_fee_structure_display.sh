#!/bin/bash

# Backup original views.py
cp axis_saas/views.py axis_saas/views.py.bak 2>/dev/null

# Replace the fee_structure function with a corrected version (forces queryset evaluation inside schema_context)
python3 << 'PYTHON_PATCH'
import re

view_file = 'axis_saas/views.py'
with open(view_file, 'r') as f:
    content = f.read()

# Find the old fee_structure function and replace it
pattern = r'(def fee_structure\(request, schema_name\):.*?)(?=\n\ndef [a-zA-Z_]|\Z)'
new_func = '''def fee_structure(request, schema_name):
    tenant = get_tenant(request, schema_name)
    edit_grade = request.GET.get('edit', '')
    with schema_context(schema_name):
        if request.method == 'POST':
            grade = request.POST.get('grade')
            monthly_fee = request.POST.get('monthly_fee')
            if grade and monthly_fee:
                obj, created = FeeStructure.objects.update_or_create(
                    grade=grade,
                    defaults={'monthly_fee': monthly_fee}
                )
                Student.objects.filter(grade=grade).update(custom_fee=monthly_fee)
                messages.success(request, f"Fee structure for {grade} saved successfully.")
            else:
                messages.error(request, "Please provide both grade and monthly fee.")
            return redirect('fee_structure', schema_name=schema_name)

        # CRITICAL FIX: evaluate queryset inside schema_context (convert to list)
        structures = list(FeeStructure.objects.all().order_by('grade'))
        print(f"[DEBUG] Tenant {schema_name}: found {len(structures)} fee structure(s)")
        for fs in structures:
            print(f"  - {fs.grade}: ₹{fs.monthly_fee}")

        form = FeeStructureForm()
        if edit_grade:
            try:
                edit_obj = FeeStructure.objects.get(grade=edit_grade)
                form = FeeStructureForm(initial={'grade': edit_obj.grade, 'monthly_fee': edit_obj.monthly_fee})
            except FeeStructure.DoesNotExist:
                pass

    context = {
        'tenant': tenant,
        'form': form,
        'fee_structures': structures,
        'edit_grade': edit_grade,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        'debug_count': len(structures),
    }
    return render(request, 'tenant/fee_structure.html', context)'''

new_content = re.sub(pattern, new_func, content, flags=re.DOTALL)
if new_content == content:
    print("ERROR: Could not locate fee_structure function. Manual fix may be required.")
    exit(1)
with open(view_file, 'w') as f:
    f.write(new_content)
print("✅ views.py patched (fee_structure now evaluates queryset inside schema_context).")
PYTHON_PATCH

# Also update the template to show the debug count (optional but helpful)
cat > /tmp/fee_structure_patch.html << 'EOF'
    {% if fee_structures %}
    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.5rem; border-radius: 0.5rem; font-size:0.8rem; display: inline-flex; align-items: center; gap: 0.5rem;">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>
        <span>{{ fee_structures|length }} fee structure(s) loaded.</span>
        {% if debug_count != fee_structures|length %}
        <span style="color: #f97316;">(debug: {{ debug_count }})</span>
        {% endif %}
    </div>
    {% else %}
    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.75rem; border-radius: 0.5rem;">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 8v4m0 4h.01"/></svg>
        <span>After adding a fee structure, all students in that grade will automatically get the monthly fee. You can also set a custom fee per student.</span>
    </div>
    {% endif %}
EOF

# Replace the info-panel section in fee_structure.html with the debug version
if grep -q "info-panel" templates/tenant/fee_structure.html; then
    # Simple replacement using awk/sed to avoid breaking the whole file
    sed -i '/{% if fee_structures %}/,/{% else %}/c\    {% if fee_structures %}\n    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.5rem; border-radius: 0.5rem; font-size:0.8rem; display: inline-flex; align-items: center; gap: 0.5rem;">\n        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>\n        <span>{{ fee_structures|length }} fee structure(s) loaded.</span>\n        {% if debug_count != fee_structures|length %}\n        <span style="color: #f97316;">(debug: {{ debug_count }})</span>\n        {% endif %}\n    </div>\n    {% else %}\n    <div class="info-panel" style="margin-top: 1rem; background: var(--surface-alt); padding: 0.75rem; border-radius: 0.5rem;">\n        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 8v4m0 4h.01"/></svg>\n        <span>After adding a fee structure, all students in that grade will automatically get the monthly fee. You can also set a custom fee per student.</span>\n    </div>\n    {% endif %}' templates/tenant/fee_structure.html
    echo "✅ Template updated with debug counter."
else
    echo "ℹ️ Template already contains the info panel; skipping template patch."
fi

echo "✅ Fix applied. Restart your Django server and hard refresh the browser."
echo "   The fee structure table should now display saved records."
