from django.contrib import admin
from django.urls import path
from django.http import HttpResponse

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

urlpatterns = [
    path('', saas_homepage, name='saas_home'),
    path('admin/', admin.site.urls),
]
