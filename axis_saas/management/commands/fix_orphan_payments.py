from django.core.management.base import BaseCommand
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, PaymentTransaction, Student

class Command(BaseCommand):
    help = 'Check for payments with missing student references and optionally delete them'

    def add_arguments(self, parser):
        parser.add_argument('--delete', action='store_true', help='Delete orphaned payments')

    def handle(self, *args, **options):
        tenants = SchoolClient.objects.filter(is_active=True).exclude(schema_name='public')
        for tenant in tenants:
            with schema_context(tenant.schema_name):
                orphaned = []
                for payment in PaymentTransaction.objects.all():
                    if not Student.objects.filter(id=payment.student_id).exists():
                        orphaned.append(payment)
                if orphaned:
                    self.stdout.write(f"Tenant {tenant.schema_name}: {len(orphaned)} orphaned payments")
                    for p in orphaned:
                        self.stdout.write(f"  - {p.receipt_number} (student_id={p.student_id})")
                    if options['delete']:
                        count = len(orphaned)
                        for p in orphaned:
                            p.delete()
                        self.stdout.write(f"  Deleted {count} orphaned payments")
                else:
                    self.stdout.write(f"Tenant {tenant.schema_name}: no orphaned payments")
