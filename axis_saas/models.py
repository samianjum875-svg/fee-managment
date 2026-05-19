from django.utils import timezone
from django.db import models
from django_tenants.models import TenantMixin, DomainMixin

class SchoolClient(TenantMixin):
    name = models.CharField(max_length=100, unique=True)
    created_on = models.DateField(auto_now_add=True)
    is_active = models.BooleanField(default=True)
    
    admin_username = models.CharField(max_length=150, default="admin_pending", help_text="Custom Superuser login username for this school instance")
    admin_password = models.CharField(max_length=128, default="AxisFallback123!", help_text="Custom Superuser login password")
    school_logo = models.FileField(upload_to="school_logos/", blank=True, null=True, help_text="Upload a school emblem or logo for the portal sidebar.")

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
    STATUS_CHOICES = [
        ('active', 'Active Enrolled'),
        ('suspended', 'Suspended'),
        ('struck_off', 'Struck Off'),
        ('graduated', 'Graduated'),
    ]
    
    GENDER_CHOICES = [
        ('male', 'Male'),
        ('female', 'Female'),
        ('other', 'Other'),
    ]

    # Required Operational Fields
    name = models.CharField(max_length=150, verbose_name="Student Name")
    father_name = models.CharField(max_length=150, verbose_name="Father Name")
    father_cnic = models.CharField(max_length=15, verbose_name="Father CNIC", help_text="Format: 35202-XXXXXXX-X")
    parent_mobile = models.CharField(max_length=15, verbose_name="Parent Mobile Number")
    grade = models.CharField(max_length=50, verbose_name="Class")
    section = models.CharField(max_length=50, verbose_name="Section")
    admission_date = models.DateField(default=timezone.now, verbose_name="Admission Date")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active', verbose_name="Status")

    # Demographic / Profiling Fields
    gender = models.CharField(max_length=10, choices=GENDER_CHOICES, blank=True, null=True, verbose_name="Gender")
    date_of_birth = models.DateField(blank=True, null=True, verbose_name="Date of Birth")
    address = models.TextField(blank=True, null=True, verbose_name="Address")

    # Secondary Metadata Fields
    photo = models.ImageField(upload_to="student_photos/", blank=True, null=True, verbose_name="Photo (Optional)")
    notes = models.TextField(blank=True, null=True, verbose_name="Notes (Optional)")
    
    roll_number = models.CharField(max_length=50, default="TEMP_TOKEN", verbose_name="Roll Number Token")
    custom_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0.00, verbose_name="Assigned Fee (RS)")
    
    enrolled_on = models.DateTimeField(auto_now_add=True)


    def save(self, *args, **kwargs):
        if not self.roll_number or self.roll_number == "TEMP_TOKEN":
            # database se is school ke aakhri student ka id record uthao
            last_student = Student.objects.all().order_by('id').last()
            if last_student and last_student.roll_number:
                try:
                    # Next incremental clean digit assignment
                    self.roll_number = str(int(last_student.roll_number) + 1)
                except ValueError:
                    self.roll_number = "1001"
            else:
                # Agar school ka pehla bacha hai, toh sequence 1001 se start hoga
                self.roll_number = "1001"
        
        # Pull base class fee configuration automatically if configured
        if not self.pk or self.custom_fee == 0.00:
            base_fee = FeeStructure.objects.filter(grade=self.grade).first()
            if base_fee:
                self.custom_fee = base_fee.monthly_fee
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} - Reg: {self.roll_number} ({self.grade}-{self.section})"


class FeeStructure(models.Model):
    grade = models.CharField(max_length=50, unique=True, verbose_name="Class / Grade")
    monthly_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0.00, verbose_name="Monthly Fee (RS)")
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Class {self.grade} - RS {self.monthly_fee}"

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        # Automatic Dynamic Cascade Update Matrix
        # Jab bhi admin is class ki fee set ya change karega, is class ke saare students ki automatic update ho jayegi
        Student.objects.filter(grade=self.grade).update(custom_fee=self.monthly_fee)
