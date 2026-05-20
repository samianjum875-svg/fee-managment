
class SafeSessionMiddleware:
    """Ensures session save always uses public schema."""
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        # After response is generated, before sending, ensure session save uses public schema
        if hasattr(request, 'session') and request.session.modified:
            from django.db import connection
            original_schema = connection.schema_name
            try:
                connection.set_schema('public')
                request.session.save()
            finally:
                connection.set_schema(original_schema)
        return response
