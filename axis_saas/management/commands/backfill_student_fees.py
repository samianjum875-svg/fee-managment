from django.core.management.base import BaseCommand
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient, Student, FeeStructure

class Command(BaseCommand):
    help = 'Backfill student custom_fee from grade fee structure for all tenants'

    def handle(self, *args, **options):
        tenants = SchoolClient.objects.filter(is_active=True).exclude(schema_name='public')
        for tenant in tenants:
            self.stdout.write(f"Processing tenant: {tenant.schema_name}")
            with schema_context(tenant.schema_name):
                updated = 0
                for student in Student.objects.all():
                    if student.custom_fee == 0:
                        fee_struct = FeeStructure.objects.filter(grade=student.grade).first()
                        if fee_struct:
                            student.custom_fee = fee_struct.monthly_fee
                            student.save(update_fields=['custom_fee'])
                            updated += 1
                            self.stdout.write(f"  Updated {student.name} (Grade {student.grade}) -> ₹{fee_struct.monthly_fee}")
                self.stdout.write(self.style.SUCCESS(f"Updated {updated} students in {tenant.schema_name}"))
