cat << 'EOF' > fix_domain.py
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'axis_saas.settings')
django.setup()
from axis_saas.models import SchoolClient, SchoolDomain

# 1. Get the public tenant
tenant = SchoolClient.objects.get(schema_name='public')

# 2. Assign localhost domain to public tenant
domain, created = SchoolDomain.objects.get_or_create(
    domain='localhost',
    tenant=tenant,
    defaults={'is_primary': True}
)

if created:
    print("[+] Domain 'localhost' registered to public schema.")
else:
    print("[!] Domain 'localhost' already exists for public.")
EOF

python3 fix_domain.py
rm fix_domain.py
