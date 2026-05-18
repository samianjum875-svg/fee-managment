from django.apps import AppConfig

class AxisSaasConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'axis_saas'

    def ready(self):
        import axis_saas.signals  # Connects structural provisioning hooks
