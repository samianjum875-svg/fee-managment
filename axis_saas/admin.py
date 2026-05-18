from django.contrib import admin
from django_tenants.admin import TenantAdminMixin
from django import forms
from django.utils.safestring import mark_safe
from .models import SchoolClient

class SchoolClientForm(forms.ModelForm):
    class Meta:
        model = SchoolClient
        fields = ['name', 'schema_name', 'admin_username', 'admin_password', 'is_active']
        widgets = {
            'admin_password': forms.PasswordInput(render_value=True),
        }

@admin.register(SchoolClient)
class SchoolClientAdmin(TenantAdminMixin, admin.ModelAdmin):
    form = SchoolClientForm
    list_display = ('name', 'schema_name', 'admin_username', 'is_active', 'created_on', 'get_admin_url_link')
    
    # Readonly field jo sirf school save hone ke baad admin panel ka dynamic link generate karegi
    readonly_fields = ('school_admin_portal_url',)
    
    fieldsets = (
        ('Master Identity Matrix', {
            'fields': ('name', 'schema_name', 'is_active')
        }),
        ('Dynamic Sub-Tenant Authority Provisioning', {
            'fields': ('admin_username', 'admin_password'),
        }),
        ('Generated Access Routes', {
            'fields': ('school_admin_portal_url',),
            'description': 'Once saved, the system automatically builds the exact landing gate link for this school node below.'
        }),
    )

    def school_admin_portal_url(self, obj):
        if obj.pk and obj.schema_name != 'public':
            # Dynamic secure URL generation with port 8000 for local development
            target_url = f"http://{obj.schema_name}.localhost:8000/admin/"
            return mark_safe(f'<a href="{target_url}" target="_blank" style="background: #10b981; color: white; padding: 8px 16px; border-radius: 6px; text-decoration: none; font-weight: bold; display: inline-block;">🚀 Open {obj.name} Admin Panel</a>')
        return "Link will be generated automatically after you click Save below."
    
    school_admin_portal_url.short_description = "Direct Admin Access Gate"

    def get_admin_url_link(self, obj):
        if obj.schema_name != 'public':
            target_url = f"http://{obj.schema_name}.localhost:8000/admin/"
            return mark_safe(f'<a href="{target_url}" target="_blank" style="color: #38bdf8; font-weight: bold;">Open Portal</a>')
        return "-"
    get_admin_url_link.short_description = "Quick Portal Link"

    def has_module_permission(self, request):
        return request.tenant.schema_name == 'public'

    def has_view_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'
