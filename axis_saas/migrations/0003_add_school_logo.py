from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('axis_saas', '0002_alter_schoolclient_name'),
    ]

    operations = [
        migrations.AddField(
            model_name='schoolclient',
            name='school_logo',
            field=models.FileField(blank=True, null=True, upload_to='school_logos/', help_text='Upload a school emblem or logo for the portal sidebar.'),
        ),
    ]
