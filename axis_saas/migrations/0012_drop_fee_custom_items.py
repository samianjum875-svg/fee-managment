# axis_saas/migrations/0012_drop_fee_custom_items.py
from django.db import migrations

class Migration(migrations.Migration):

    dependencies = [
        ('axis_saas', '0011_remove_feerecord_extra_charges_and_more'),
    ]

    operations = [
        migrations.RunSQL(
            sql="ALTER TABLE axis_saas_student DROP COLUMN IF EXISTS fee_custom_items CASCADE;",
            reverse_sql="ALTER TABLE axis_saas_student ADD COLUMN fee_custom_items JSONB NULL;"
        ),
    ]
