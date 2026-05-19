import os
import django
from django.db import connection

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
django.setup()

def fix_database_and_models():
    with connection.cursor() as cursor:
        print("[*] Force dropping existing axis_saas tables to clear schema...")
        # Conflict wale tables ko force drop karo
        cursor.execute("DROP TABLE IF EXISTS axis_saas_student CASCADE;")
        cursor.execute("DROP TABLE IF EXISTS axis_saas_schoolclient CASCADE;")
        cursor.execute("DROP TABLE IF EXISTS axis_saas_schooldomain CASCADE;")
        cursor.execute("DROP TABLE IF EXISTS axis_saas_feestructure CASCADE;")
        
        # Migration record ko pura clear karo
        cursor.execute("DELETE FROM django_migrations WHERE app = 'axis_saas';")
        print("[+] Tables dropped and migration history cleared.")

if __name__ == "__main__":
    fix_database_and_models()
