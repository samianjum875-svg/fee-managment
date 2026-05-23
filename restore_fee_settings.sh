#!/bin/bash

# Backup views.py just in case
cp axis_saas/views.py axis_saas/views.py.bak 2>/dev/null

# Check if fee_settings already exists
if grep -q "def fee_settings" axis_saas/views.py; then
    echo "✅ fee_settings function already present. No changes needed."
else
    echo "⚠️ fee_settings function not found. Adding it now..."
    cat >> axis_saas/views.py << 'EOF'

# ------------------- Fee Settings -------------------
def fee_settings(request, schema_name):
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        settings_obj, created = SchoolFeeSettings.objects.get_or_create(pk=1)
        if request.method == 'POST':
            form = FeeSettingsForm(request.POST, instance=settings_obj)
            if form.is_valid():
                form.save()
                messages.success(request, "Fee settings updated.")
                return redirect('fee_settings', schema_name=schema_name)
        else:
            form = FeeSettingsForm(instance=settings_obj)
    context = {'tenant': tenant, 'form': form, 'logo_url': tenant.school_logo.url if tenant.school_logo else None}
    return render(request, 'tenant/fee_settings.html', context)
EOF
    echo "✅ fee_settings function added successfully."
fi

echo "👉 Restart your Django server now:"
echo "   python3 manage.py runserver"
