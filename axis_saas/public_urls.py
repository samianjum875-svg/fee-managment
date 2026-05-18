from django.contrib import admin
from django.urls import path
from django.http import HttpResponse
from axis_saas.models import SchoolClient

def saas_homepage(request):
    tenants = SchoolClient.objects.exclude(schema_name='public')
    tenant_list_html = ""
    
    for t in tenants:
        domain_obj = t.domains.first()
        if domain_obj:
            # Generate link dynamically using the actual domain in the database
            url = f"http://{domain_obj.domain}:8000/"
            tenant_list_html += f'<li><strong>{t.name}</strong> (Schema: {t.schema_name}) -> <a href="{url}" target="_blank" style="color: #38bdf8; text-decoration: underline;">Open Isolated Portal</a></li>'
    
    if not tenant_list_html:
        tenant_list_html = "<p style='color: #94a3b8;'>No school nodes provisioned yet.</p>"

    return HttpResponse(f'''
        <style>
            body {{ font-family: 'Segoe UI', sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }}
            .card {{ background: #1e293b; padding: 40px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.3); border: 1px solid #334155; max-width: 600px; width: 100%; }}
            h1 {{ color: #38bdf8; margin-bottom: 10px; text-align: center; }}
            ul {{ background: #0f172a; padding: 20px; border-radius: 8px; list-style-type: none; margin: 20px 0; border: 1px solid #334155; }}
            li {{ margin-bottom: 12px; border-bottom: 1px solid #1e293b; padding-bottom: 8px; }}
            a {{ text-decoration: none; font-weight: bold; }}
            .btn {{ display: block; text-align: center; background: #38bdf8; color: #0f172a; padding: 10px; border-radius: 6px; text-decoration: none; font-weight: bold; margin-top: 15px; }}
        </style>
        <div class="card">
            <h1>AXIS SaaS Engine Active 🚀</h1>
            <p style="text-align: center; color: #94a3b8;">Main Core Platform Master Node.</p>
            
            <h3 style="color: #34d399;">Active Dynamic School Portals:</h3>
            <ul>{tenant_list_html}</ul>
            
            <a class="btn" href="/admin/">Go to Master Administration Grid (Create Schools)</a>
        </div>
    ''')

urlpatterns = [
    path('', saas_homepage, name='saas_home'),
    path('admin/', admin.site.urls),
]
