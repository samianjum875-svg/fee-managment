from django.contrib import admin
from django_tenants.admin import TenantAdminMixin
from django import forms
from django.utils.safestring import mark_safe
from django.core.exceptions import ValidationError
from .models import SchoolClient


class TenantOnlyAdminMixin:
    def has_module_permission(self, request):
        return request.tenant.schema_name != 'public'
    def has_view_permission(self, request, obj=None):
        return request.tenant.schema_name != 'public'
    def has_add_permission(self, request):
        return request.tenant.schema_name != 'public'
    def has_change_permission(self, request, obj=None):
        return request.tenant.schema_name != 'public'
    def has_delete_permission(self, request, obj=None):
        return request.tenant.schema_name != 'public'

class PublicOnlyAdminMixin:
    def has_module_permission(self, request):
        return request.tenant.schema_name == 'public'
    def has_view_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.exclude(schema_name='public')
    def has_add_permission(self, request):
        return request.tenant.schema_name == 'public'
    def has_change_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'
    def has_delete_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

class SchoolClientForm(forms.ModelForm):
    class Meta:
        model = SchoolClient
        fields = ['name', 'schema_name', 'admin_username', 'admin_password', 'is_active']
        widgets = {
            'admin_password': forms.PasswordInput(render_value=True),
        }

    def clean_schema_name(self):
        schema = self.cleaned_data.get('schema_name').lower().strip()
        if self.instance.pk and self.instance.schema_name == 'public' and schema != 'public':
            raise ValidationError("CRITICAL ERROR: The core public operational schema token cannot be renamed.")
        
        from django.db import connection
        with connection.cursor() as cursor:
            cursor.execute("SELECT schema_name FROM information_schema.schemata WHERE schema_name = %s", [schema])
            exists = cursor.fetchone()
        
        if not self.instance.pk and exists:
            raise ValidationError(f"⚠️ SECURITY BREACH BLOCK: The schema name '{schema}' physically exists in PostgreSQL as an active partition! Choose a unique routing path.")
        return schema

@admin.register(SchoolClient)
class SchoolClientAdmin(TenantAdminMixin, admin.ModelAdmin):
    form = SchoolClientForm
    list_display = ('name', 'schema_name', 'admin_username', 'is_active', 'created_on', 'get_admin_url_link')
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

    def get_readonly_fields(self, request, obj=None):
        if obj and obj.schema_name == 'public':
            return self.readonly_fields + ('schema_name', 'admin_username', 'is_active')
        return self.readonly_fields

    def has_delete_permission(self, request, obj=None):
        if obj and obj.schema_name == 'public':
            return False
        return request.tenant.schema_name == 'public'

    def school_admin_portal_url(self, obj):
        if obj.pk and obj.schema_name != 'public':
            target_url = f"http://localhost:8000/portal/{obj.schema_name}/"
            return mark_safe(f'<a href="{target_url}" target="_blank" style="background: #10b981; color: white; padding: 8px 16px; border-radius: 6px; text-decoration: none; font-weight: bold; display: inline-block;">🚀 Open {obj.name} School Portal</a>')
        return "Link will be generated automatically after you click Save below."
    
    school_admin_portal_url.short_description = "Direct School Portal Gate"
    
    def get_admin_url_link(self, obj):
        if obj.schema_name != 'public':
            target_url = f"http://localhost:8000/portal/{obj.schema_name}/"
            return mark_safe(f'<a href="{target_url}" target="_blank" style="color: #38bdf8; font-weight: bold;">Open School Portal</a>')
        return "MASTER NODE"
    get_admin_url_link.short_description = "Quick Portal Link"

    def has_module_permission(self, request):
        return request.tenant.schema_name == 'public'

    def has_view_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.exclude(schema_name='public')


# --- AXIS Student Registry Injection ---
from .models import Student

@admin.register(Student)
class StudentAdmin(TenantOnlyAdminMixin, admin.ModelAdmin):
    list_display = ('roll_number', 'name', 'grade', 'section', 'status', 'enrolled_on')
    list_filter = ('grade', 'section', 'status', 'gender')
    search_fields = ('name', 'roll_number', 'father_name', 'father_cnic')
    ordering = ('-enrolled_on',)
    
    readonly_fields = ('display_student_fee',)

    fieldsets = (
        ('Core Enrollment Records', {
            'fields': ('name', 'roll_number', 'status')
        }),
        ('Academic & Class Placement', {
            'fields': ('grade', 'section', 'admission_date')
        }),
        ('Parental & Verification Matrix', {
            'fields': ('father_name', 'father_cnic', 'parent_mobile')
        }),
        ('Financial Status Matrix', {
            'fields': ('display_student_fee', 'custom_fee'),
            'description': 'Current fee parameters loaded dynamically via matching class standard configurations.',
        }),
    )

    def display_student_fee(self, obj):
        if obj.pk:
            return f"RS {obj.custom_fee}"
        return "Will be computed based on selected class standard fee roster."
    display_student_fee.short_description = "Active Monthly Fee Structure"
    
    def get_readonly_fields(self, request, obj=None):
        base_fields = list(self.readonly_fields)
        if obj:
            base_fields.append('roll_number')
        return tuple(base_fields)

# --- AXIS Fee Structure Registry Injection ---
from .models import FeeStructure

@admin.register(FeeStructure)
class FeeStructureAdmin(TenantOnlyAdminMixin, admin.ModelAdmin):
    list_display = ('grade', 'monthly_fee', 'updated_at')
    search_fields = ('grade',)

# --- AXIS SECURITY HARDENING: MULTI-TENANT ISOLATION OVERRIDE ---
from django.contrib.auth.models import User, Group
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.admin import GroupAdmin as BaseGroupAdmin

try:
    admin.site.unregister(User)
    admin.site.unregister(Group)
except admin.sites.NotRegistered:
    pass

@admin.register(User)
class TenantSecuredUserAdmin(BaseUserAdmin):
    def has_module_permission(self, request):
        return request.tenant.schema_name == 'public'

    def has_view_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

    def has_add_permission(self, request):
        return request.tenant.schema_name == 'public'

    def has_change_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

    def has_delete_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

    def save_model(self, request, obj, form, change):
        if request.tenant.schema_name != 'public':
            obj.is_superuser = False
        super().save_model(request, obj, form, change)


@admin.register(Group)
class TenantSecuredGroupAdmin(BaseGroupAdmin):
    def has_module_permission(self, request):
        return request.tenant.schema_name == 'public'

    def has_view_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

    def has_add_permission(self, request):
        return request.tenant.schema_name == 'public'

    def has_change_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

    def has_delete_permission(self, request, obj=None):
        return request.tenant.schema_name == 'public'

# Register Fee models
from .models import FeeRecord, PaymentTransaction, SchoolFeeSettings

@admin.register(FeeRecord)
class FeeRecordAdmin(admin.ModelAdmin):
    list_display = ('student', 'month', 'year', 'amount', 'paid_amount', 'status', 'due_date')
    list_filter = ('status', 'month', 'year')
    search_fields = ('student__name', 'student__roll_number')

@admin.register(PaymentTransaction)
class PaymentTransactionAdmin(admin.ModelAdmin):
    list_display = ('receipt_number', 'student', 'amount', 'payment_date', 'payment_type')
    list_filter = ('payment_type', 'payment_mode', 'payment_date')
    search_fields = ('receipt_number', 'student__name', 'student__father_cnic')

@admin.register(SchoolFeeSettings)
class SchoolFeeSettingsAdmin(admin.ModelAdmin):
    list_display = ('fee_generation_day', 'due_date_offset', 'late_fee_penalty', 'updated_at')
