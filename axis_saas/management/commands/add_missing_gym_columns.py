from django.core.management.base import BaseCommand
from django.db import connection
from django_tenants.utils import schema_context
from axis_saas.models import SchoolClient

class Command(BaseCommand):
    help = 'Add missing columns to gym tables for all tenant schemas'

    def handle(self, *args, **options):
        tenants = SchoolClient.objects.exclude(schema_name='public')
        for tenant in tenants:
            self.stdout.write(f"Processing {tenant.schema_name}...")
            with schema_context(tenant.schema_name):
                with connection.cursor() as cursor:
                    # Check and add is_cancelled to gymsubscription
                    cursor.execute("""
                        SELECT column_name FROM information_schema.columns 
                        WHERE table_name='axis_saas_gymsubscription' AND column_name='is_cancelled'
                    """)
                    if not cursor.fetchone():
                        cursor.execute("ALTER TABLE axis_saas_gymsubscription ADD COLUMN is_cancelled boolean DEFAULT false")
                        self.stdout.write("  Added is_cancelled column")
                    # Check and add cancelled_on
                    cursor.execute("""
                        SELECT column_name FROM information_schema.columns 
                        WHERE table_name='axis_saas_gymsubscription' AND column_name='cancelled_on'
                    """)
                    if not cursor.fetchone():
                        cursor.execute("ALTER TABLE axis_saas_gymsubscription ADD COLUMN cancelled_on date")
                        self.stdout.write("  Added cancelled_on column")
                    # Check and add updated_at to gymattendance
                    cursor.execute("""
                        SELECT column_name FROM information_schema.columns 
                        WHERE table_name='axis_saas_gymattendance' AND column_name='updated_at'
                    """)
                    if not cursor.fetchone():
                        cursor.execute("ALTER TABLE axis_saas_gymattendance ADD COLUMN updated_at timestamp with time zone")
                        self.stdout.write("  Added updated_at column")
        self.stdout.write(self.style.SUCCESS("All missing columns added."))
