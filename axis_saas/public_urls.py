from django.contrib import admin, messages
from django.urls import path
from django.http import HttpResponse, HttpResponseNotFound
from django.shortcuts import redirect, render
from django.conf import settings
from django.conf.urls.static import static
from django import forms
from axis_saas.models import SchoolClient
from .models import Student
from .tenant_views import StudentAdmissionForm
from django_tenants.utils import schema_context

# ----------------------------------------------------------------------
# DECORATOR: ensures user is logged into the correct tenant schema
# ----------------------------------------------------------------------
def tenant_login_required(view_func):
    def wrapper(request, schema_name, *args, **kwargs):
        tenant = get_school_tenant(schema_name)
        if not tenant:
            return HttpResponseNotFound('School not found')
        # Critical: check both authentication flag AND matching schema
        if not request.session.get('school_admin_authenticated') or \
           request.session.get('school_admin_schema') != tenant.schema_name:
            # clear stale session data
            request.session.pop('school_admin_authenticated', None)
            request.session.pop('school_admin_schema', None)
            return redirect(f'/portal/{tenant.schema_name}/login/')
        return view_func(request, schema_name, tenant=tenant, *args, **kwargs)
    return wrapper

# ----------------------------------------------------------------------
# Helper: fetch tenant from public schema (safe)
# ----------------------------------------------------------------------
def get_school_tenant(schema_name):
    schema_name = schema_name.lower().strip()
    with schema_context('public'):
        tenant = SchoolClient.objects.filter(schema_name__iexact=schema_name, is_active=True).first()
    return tenant

# ----------------------------------------------------------------------
# Public home
# ----------------------------------------------------------------------
def saas_homepage(request):
    return HttpResponse('<h1>AXIS Engine Active</h1><p>School portals: /portal/&lt;schema_name&gt;/</p>')

# ----------------------------------------------------------------------
# Login / Logout (public, no decorator)
# ----------------------------------------------------------------------
def school_login(request, schema_name):
    tenant = get_school_tenant(schema_name)
    if not tenant:
        return HttpResponseNotFound('School not found')
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        if username == tenant.admin_username and password == tenant.admin_password:
            request.session['school_admin_authenticated'] = True
            request.session['school_admin_schema'] = tenant.schema_name
            request.session.save()
            return redirect(f'/portal/{tenant.schema_name}/')
        return render(request, 'tenant/login.html', {'tenant': tenant, 'error': 'Invalid credentials'})
    return render(request, 'tenant/login.html', {'tenant': tenant})

def school_logout(request, schema_name):
    request.session.flush()
    return redirect(f'/portal/{schema_name}/login/')

# ----------------------------------------------------------------------
# Protected views (tenant-specific session required)
# ----------------------------------------------------------------------
@tenant_login_required
def school_dashboard(request, schema_name, tenant=None):
    logo_url = tenant.school_logo.url if tenant.school_logo else None
    return render(request, 'tenant/dashboard.html', {'tenant': tenant, 'logo_url': logo_url})

@tenant_login_required
def school_students_list(request, schema_name, tenant=None):
    with schema_context(tenant.schema_name):
        students = Student.objects.all().order_by('-id')
    return render(request, 'tenant/students_list.html', {'tenant': tenant, 'students': students})

@tenant_login_required
def school_add_student(request, schema_name, tenant=None):
    with schema_context(tenant.schema_name):
        if request.method == 'POST':
            form = StudentAdmissionForm(request.POST)
            if form.is_valid():
                student = form.save(commit=False)
                total = Student.objects.count() + 1
                student.roll_number = f"AX-{tenant.schema_name.upper()}-2026-{total:04d}"
                student.save()
                messages.success(request, f'Student {student.name} added')
                return redirect('school_portal_students', schema_name=tenant.schema_name)
        else:
            form = StudentAdmissionForm()
    logo_url = tenant.school_logo.url if tenant.school_logo else None
    return render(request, 'tenant/student_form.html', {'tenant': tenant, 'form': form, 'logo_url': logo_url})

@tenant_login_required
def school_settings(request, schema_name, tenant=None):
    # Simple version – can be extended later
    logo_url = tenant.school_logo.url if tenant.school_logo else None
    return render(request, 'tenant/settings.html', {'tenant': tenant, 'logo_url': logo_url})

# ----------------------------------------------------------------------
# URL patterns
# ----------------------------------------------------------------------
urlpatterns = [
    path('portal/<slug:schema_name>/students/', school_students_list, name='school_portal_students'),
    path('portal/<slug:schema_name>/students/add/', school_add_student, name='school_add_student'),
    path('portal/<slug:schema_name>/', school_dashboard, name='school_portal'),
    path('portal/<slug:schema_name>/login/', school_login, name='school_portal_login'),
    path('portal/<slug:schema_name>/logout/', school_logout, name='school_portal_logout'),
    path('portal/<slug:schema_name>/settings/', school_settings, name='school_portal_settings'),
    path('', saas_homepage),
    path('admin/', admin.site.urls),
]
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
