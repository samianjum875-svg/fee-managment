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
