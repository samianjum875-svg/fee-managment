from django.core.management.base import BaseCommand
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, PaymentTransaction, Student

class Command(BaseCommand):
    help = 'Check payment integrity and force a test query'

    def handle(self, *args, **options):
        for tenant in SchoolClient.objects.filter(is_active=True).exclude(schema_name='public'):
            with schema_context(tenant.schema_name):
                total = PaymentTransaction.objects.count()
                recent = PaymentTransaction.objects.order_by('-payment_date')[:5]
                self.stdout.write(f"{tenant.schema_name}: {total} payments, recent count = {recent.count()}")
                if total > 0 and recent.count() == 0:
                    self.stdout.write(self.style.ERROR(f"  ❌ CRITICAL: Payments exist but recent query returns empty!"))
                    # Try to fetch first payment to see if date is None
                    first = PaymentTransaction.objects.first()
                    if first:
                        self.stdout.write(f"     First payment date: {first.payment_date}")
                else:
                    self.stdout.write(self.style.SUCCESS(f"  ✅ OK"))
