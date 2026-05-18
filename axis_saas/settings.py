import environ
import os
from pathlib import Path

env = environ.Env(DEBUG=(bool, False))
BASE_DIR = Path(__file__).resolve().parent.parent
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

SECRET_KEY = env('SECRET_KEY')
DEBUG = env('DEBUG')

ALLOWED_HOSTS = ['localhost', '.localhost', '127.0.0.1']

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django_tenants.middleware.main.TenantMainMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    # ANTI-EXPLOIT SHIELD: Absolute protection against concurrent sessions, session bleeding, and back-button caching
    'axis_saas.settings.CrossTenantSessionIsolationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'axis_saas.public_urls'
PUBLIC_SCHEMA_URLCONF = 'axis_saas.public_urls'
TENANT_URLCONF = 'axis_saas.tenant_urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [os.path.join(BASE_DIR, 'templates')],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'axis_saas.wsgi.application'

DATABASES = {
    'default': env.db()
}
DATABASES['default']['ENGINE'] = 'django_tenants.postgresql_backend'

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'

# ==============================================================================
# MULTI-TENANT CONFIGURATION MATRIX
# ==============================================================================
SHARED_APPS = [
    'django_tenants',
    'axis_saas',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

TENANT_APPS = [
    'axis_saas',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

INSTALLED_APPS = []
for app in SHARED_APPS:
    if app not in INSTALLED_APPS:
        INSTALLED_APPS.append(app)
for app in TENANT_APPS:
    if app not in INSTALLED_APPS:
        INSTALLED_APPS.append(app)

TENANT_MODEL = 'axis_saas.SchoolClient'
TENANT_DOMAIN_MODEL = 'axis_saas.SchoolDomain'

DATABASE_ROUTERS = (
    'django_tenants.routers.TenantSyncRouter',
)

# ==============================================================================
# SECURE COOKIE & SESSION HARDENING
# ==============================================================================
SESSION_COOKIE_DOMAIN = None
CSRF_COOKIE_DOMAIN = None
SESSION_SAVE_EVERY_REQUEST = True

CSRF_TRUSTED_ORIGINS = [
    'http://localhost:8000',
    'http://127.0.0.1:8000',
    'http://*.localhost:8000',
]

CSRF_COOKIE_HTTPONLY = False
SESSION_COOKIE_HTTPONLY = True
CSRF_USE_SESSIONS = False

SESSION_EXPIRE_AT_BROWSER_CLOSE = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'

# ==============================================================================
# HARDENED SHIELD: MULTI-TENANT CONCURRENT PROTECTION & CACHE DESTRUCTION
# ==============================================================================
from django.contrib.auth import logout
from django.utils.deprecation import MiddlewareMixin

class CrossTenantSessionIsolationMiddleware(MiddlewareMixin):
    def process_request(self, request):
        if hasattr(request, 'user') and request.user.is_authenticated:
            current_schema = getattr(request, 'tenant', None)
            current_schema_name = current_schema.schema_name if current_schema else 'public'
            
            session_schema = request.session.get('_auth_tenant_schema_token')
            session_user_id = request.session.get('_auth_user_id')
            
            # Cross-Tenant Conflict Detection Engine
            if session_schema is None:
                request.session['_auth_tenant_schema_token'] = current_schema_name
                request.session['_auth_active_user_fingerprint'] = f"{current_schema_name}_{session_user_id}"
            elif session_schema != current_schema_name:
                # Boom! User tried to open another tenant dashboard in the same browser session.
                # Flush everything to protect the application boundaries.
                logout(request)
                request.session.flush()
                
    def process_response(self, request, response):
        # Explicit Cache Destruction Matrix - Prevents Back Button Exploits after logout
        response['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0'
        response['Pragma'] = 'no-cache'
        response['Expires'] = '0'
        return response
