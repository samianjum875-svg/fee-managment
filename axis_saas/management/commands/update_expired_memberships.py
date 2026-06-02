from django.core.management.base import BaseCommand
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, GymCustomer
from datetime import date

class Command(BaseCommand):
    help = 'Update expired customers to status expired'

    def handle(self, *args, **options):
        today = date.today()
        tenants = SchoolClient.objects.filter(is_active=True, tenant_type='gym').exclude(schema_name='public')
        updated_total = 0
        for tenant in tenants:
            with schema_context(tenant.schema_name):
                expired = GymCustomer.objects.filter(
                    status='active',
                    membership_end__lt=today
                )
                count = expired.count()
                if count:
                    expired.update(status='expired')
                    self.stdout.write(f"{tenant.schema_name}: {count} customers expired")
                    updated_total += count
        self.stdout.write(self.style.SUCCESS(f"Total updated: {updated_total}"))
