import environ
import os
from pathlib import Path

env = environ.Env(DEBUG=(bool, False))
BASE_DIR = Path(__file__).resolve().parent.parent
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

SECRET_KEY = os.environ.get('SECRET_KEY', 'django-insecure-fallback-for-build-only')
DEBUG = env('DEBUG', default=False)

ALLOWED_HOSTS = os.environ.get('ALLOWED_HOSTS', '*').split(',')

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'axis_saas.middleware.url_tenant_middleware.URLPathTenantMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
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
                'axis_saas.context_processors.tenant_processor',   # ✅ ADD THIS LINE
            ],
        },
    },
]

WSGI_APPLICATION = 'axis_saas.wsgi.application'

# Database – force django_tenants backend
if os.environ.get('DATABASE_URL'):
    import dj_database_url
    DATABASES = {
        'default': dj_database_url.config(conn_max_age=600, ssl_require=True)
    }
    DATABASES['default']['ENGINE'] = 'django_tenants.postgresql_backend'
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django_tenants.postgresql_backend',
            'NAME': 'dummy',
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'Asia/Karachi'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = '/data/staticfiles'
MEDIA_ROOT = '/data/media'
MEDIA_URL = '/media/'

STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

LOGIN_URL = 'tenant_login'
LOGIN_REDIRECT_URL = 'dashboard'
LOGOUT_REDIRECT_URL = 'tenant_login'

# Multi-tenant
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

INSTALLED_APPS = SHARED_APPS + [app for app in TENANT_APPS if app not in SHARED_APPS]

TENANT_MODEL = 'axis_saas.SchoolClient'
TENANT_DOMAIN_MODEL = 'axis_saas.SchoolDomain'
TENANT_SUBFOLDER_PREFIX = 'portal'

# ✅ Fix for "No tenant for hostname" error – use public schema on root URL
PUBLIC_SCHEMA_NAME = 'public'
TENANT_LIMIT_SET_CALLS = True

DATABASE_ROUTERS = (
    'django_tenants.routers.TenantSyncRouter',
)

# Security
SESSION_COOKIE_DOMAIN = None
CSRF_COOKIE_DOMAIN = None
SESSION_ENGINE = 'django.contrib.sessions.backends.db'
SESSION_SAVE_EVERY_REQUEST = False
CSRF_TRUSTED_ORIGINS = os.environ.get('CSRF_TRUSTED_ORIGINS', 'http://localhost:8000').split(',')
SESSION_COOKIE_PATH = '/'
SESSION_FILE_PATH = '/tmp/django_sessions/'