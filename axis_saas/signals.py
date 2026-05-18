from django.dispatch import receiver
from django_tenants.signals import post_schema_sync
from django_tenants.utils import schema_context
from django.contrib.auth import get_user_model

@receiver(post_schema_sync)
def provision_secure_tenant_admin(sender, tenant, **kwargs):
    if tenant.schema_name == 'public':
        return

    User = get_user_model()
    
    # Read the custom credentials written by user during form submission!
    u_name = tenant.admin_username
    u_pass = tenant.admin_password
    u_email = f"{u_name}@{tenant.schema_name}.com"
    
    if not u_name or not u_pass:
        return # Skip processing if field mapping is completely void

    with schema_context(tenant.schema_name):
        if not User.objects.filter(username=u_name).exists():
            User.objects.create_superuser(
                username=u_name,
                email=u_email,
                password=u_pass
            )
            print(f"🚀 [DYNAMIC SYNC] Operational superuser '{u_name}' provisioned into tenant schema '{tenant.schema_name}' successfully.")
