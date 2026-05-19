from django.contrib import admin
from django.urls import path
from django.http import HttpResponse, HttpResponseNotFound
from django.shortcuts import redirect
from django_tenants.utils import schema_context
from django.contrib.auth import views as auth_views

from axis_saas.models import SchoolClient
from axis_saas.tenant_views import tenant_dashboard, add_student_instance, fee_management_dashboard


def saas_homepage(request):
    # Strictly clean, static generic entry point with zero information disclosure
    return HttpResponse('''
        <style>
            body { font-family: 'Segoe UI', sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
            .card { background: #1e293b; padding: 40px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.3); border: 1px solid #334155; max-width: 500px; width: 100%; text-align: center; }
            h1 { color: #38bdf8; margin-bottom: 10px; }
            p { color: #94a3b8; font-size: 1.1em; line-height: 1.5; }
        </style>
        <div class="card">
            <h1>AXIS Engine Active 🚀</h1>
            <p>Welcome to the AXIS Cloud Platform. Direct portal access requires your assigned institutional sub-domain gate routing.</p>
        </div>
    ''')


def public_root(request):
    tenant = resolve_tenant_host(request)
    if tenant:
        return redirect('/portal/')
    return saas_homepage(request)


def resolve_tenant_host(request):
    host = request.get_host().split(':')[0]
    if host != 'localhost' and host.endswith('.localhost'):
        schema_name = host.split('.')[0]
        return SchoolClient.objects.filter(schema_name=schema_name, is_active=True).first()
    return None


def tenant_public_dispatch(request, path=''):
    tenant = resolve_tenant_host(request)
    if not tenant:
        return HttpResponseNotFound('Tenant domain not found for this host.')

    request.tenant = tenant
    with schema_context(tenant.schema_name):
        normalized_path = path.rstrip('/')
        if normalized_path in ['', 'portal']:
            return tenant_dashboard(request)
        if normalized_path == 'login':
            login_view = auth_views.LoginView.as_view(template_name='tenant/login.html', redirect_authenticated_user=True)
            return login_view(request)
        if normalized_path == 'logout':
            logout_view = auth_views.LogoutView.as_view(next_page='tenant_login')
            return logout_view(request)
        if normalized_path == 'students/add':
            return add_student_instance(request)
        if normalized_path == 'fees':
            return fee_management_dashboard(request)

    return HttpResponseNotFound('Tenant portal path not found.')

urlpatterns = [
    path('', public_root, name='saas_home'),
    path('admin/', admin.site.urls),
    path('<path:path>', tenant_public_dispatch),
]
