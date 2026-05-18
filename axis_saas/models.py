from django.db import models
from django_tenants.models import TenantMixin, DomainMixin

class SchoolClient(TenantMixin):
    name = models.CharField(max_length=100)
    created_on = models.DateField(auto_now_add=True)
    is_active = models.BooleanField(default=True)
    
    # Custom fields requested by user to explicitly manage custom authorization keys
    admin_username = models.CharField(max_length=150, default="admin_pending", help_text="Custom Superuser login username for this school instance")
    admin_password = models.CharField(max_length=128, default="AxisFallback123!", help_text="Custom Superuser login password")

    auto_create_schema = True

    def __str__(self):
        return f"{self.name}"

    def save(self, *args, **kwargs):
        is_new = self.pk is None
        super().save(*args, **kwargs)
        if is_new and self.schema_name != 'public':
            SchoolDomain.objects.get_or_create(
                domain=f"{self.schema_name}.localhost",
                tenant=self,
                is_primary=True
            )

class SchoolDomain(DomainMixin):
    pass

class Student(models.Model):
    name = models.CharField(max_length=150)
    roll_number = models.CharField(max_length=50, unique=True)
    grade = models.CharField(max_length=50)
    enrolled_on = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} ({self.roll_number})"
