from django.db import connection
from django_tenants.middleware import TenantMainMiddleware
from django_tenants.utils import get_tenant_model
from django.urls import resolve
from django.http import Http404

class URLPathTenantMiddleware(TenantMainMiddleware):
    """
    Custom tenant middleware: only look for tenant if the URL path starts with '/portal/'.
    Otherwise, use the public schema.
    """
    def __call__(self, request):
        # If request path does NOT start with /portal/, use public schema
        if not request.path_info.startswith('/portal/'):
            # Set tenant to None (public schema) – django-tenants will handle it
            request.tenant = None
            connection.set_schema_to_public()   # restore public schema
            return self.get_response(request)

        # Path starts with /portal/ – extract schema_name from URL
        schema_name = None
        try:
            match = resolve(request.path_info)
            if 'schema_name' in match.kwargs:
                schema_name = match.kwargs['schema_name']
        except:
            pass

        if schema_name:
            TenantModel = get_tenant_model()
            try:
                tenant = TenantModel.objects.get(schema_name=schema_name)
                request.tenant = tenant
                connection.set_tenant(request.tenant)
                return self.get_response(request)
            except TenantModel.DoesNotExist:
                raise Http404("Tenant not found")

        # Fallback to default domain‑based behaviour (should not be reached)
        return super().__call__(request)