from django_tenants.utils import get_public_schema_name

class DummyTenant:
    """Fake tenant used when request.tenant is None (public schema)."""
    def __init__(self):
        self.schema_name = get_public_schema_name()

def tenant_processor(request):
    """Ensure request.tenant is never None for admin templates."""
    if not hasattr(request, 'tenant') or request.tenant is None:
        request.tenant = DummyTenant()
    return {}