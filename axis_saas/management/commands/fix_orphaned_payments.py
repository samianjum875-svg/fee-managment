from django.core.management.base import BaseCommand
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, PaymentTransaction, Student

class Command(BaseCommand):
    help = 'Delete or reassign payments with missing student references'

    def add_arguments(self, parser):
        parser.add_argument('--delete', action='store_true', help='Delete orphaned payments')
        parser.add_argument('--reassign-to', type=int, help='Reassign to a student ID (only if --delete not used)')

    def handle(self, *args, **options):
        tenants = SchoolClient.objects.filter(is_active=True).exclude(schema_name='public')
        for tenant in tenants:
            with schema_context(tenant.schema_name):
                orphaned = []
                for payment in PaymentTransaction.objects.all():
                    if not Student.objects.filter(id=payment.student_id).exists():
                        orphaned.append(payment)
                if orphaned:
                    self.stdout.write(self.style.WARNING(f"Tenant {tenant.schema_name}: {len(orphaned)} orphaned payments"))
                    for p in orphaned:
                        self.stdout.write(f"  - {p.receipt_number} (student_id={p.student_id})")
                    if options['delete']:
                        count = len(orphaned)
                        for p in orphaned:
                            p.delete()
                        self.stdout.write(self.style.SUCCESS(f"  Deleted {count} orphaned payments"))
                    elif options['reassign_to']:
                        new_student = Student.objects.filter(id=options['reassign_to']).first()
                        if new_student:
                            count = len(orphaned)
                            for p in orphaned:
                                p.student = new_student
                                p.save()
                            self.stdout.write(self.style.SUCCESS(f"  Reassigned {count} payments to student {new_student.name}"))
                        else:
                            self.stdout.write(self.style.ERROR(f"  Student ID {options['reassign_to']} not found"))
                    else:
                        self.stdout.write("  Use --delete or --reassign-to to clean up")
                else:
                    self.stdout.write(f"Tenant {tenant.schema_name}: no orphaned payments")
