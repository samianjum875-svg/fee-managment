#!/bin/bash

echo "🔧 Fixing tenant isolation..."

# 1. Create middleware if not exists
mkdir -p axis_saas
cat > axis_saas/middleware.py << 'MIDDLEWARE'
from django.db import connection
from django.utils.deprecation import MiddlewareMixin
import re

class PublicSchemaMiddleware(MiddlewareMixin):
    def process_request(self, request):
        match = re.search(r'/portal/([^/]+)/', request.path)
        if match:
            schema_name = match.group(1)
            try:
                from axis_saas.models import SchoolClient
                if SchoolClient.objects.filter(schema_name=schema_name, is_active=True).exists():
                    connection.set_schema(schema_name)
                    request.tenant_schema = schema_name
                else:
                    connection.set_schema('public')
            except:
                connection.set_schema('public')
        else:
            connection.set_schema('public')
    
    def process_response(self, request, response):
        connection.set_schema('public')
        return response
MIDDLEWARE

# 2. Add middleware to settings.py if not already present
if ! grep -q "axis_saas.middleware.PublicSchemaMiddleware" axis_saas/settings.py; then
    sed -i '/django_tenants.middleware.main.TenantMainMiddleware/a \    \'axis_saas.middleware.PublicSchemaMiddleware\',' axis_saas/settings.py
    echo "✅ Added PublicSchemaMiddleware to settings.py"
else
    echo "ℹ️ Middleware already present"
fi

# 3. Ensure public_urls.py uses the correct schema (fallback)
# No changes needed if middleware works, but add safety in views

# 4. Restart message
echo "✅ Fix applied. Restart Django server:"
echo "   python manage.py runserver"
