from django.utils import timezone
from django.db import models
from django_tenants.models import TenantMixin, DomainMixin
from decimal import Decimal
from datetime import date, timedelta

# ------------------- Tenant Model -------------------
class SchoolClient(TenantMixin):
    name = models.CharField(max_length=100, unique=True)
    created_on = models.DateField(auto_now_add=True)
    is_active = models.BooleanField(default=True)
    
    admin_username = models.CharField(max_length=150, default="admin_pending")
    admin_password = models.CharField(max_length=128, default="AxisFallback123!")
    school_logo = models.FileField(upload_to="school_logos/", blank=True, null=True)
    tenant_type = models.CharField(max_length=20, choices=[("school", "School"), ("gym", "Gym")], default="school")
    
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

# ------------------- Student Model -------------------
class Student(models.Model):
    STATUS_CHOICES = [
        ('active', 'Active'),
        ('suspended', 'Suspended'),
        ('graduated', 'Graduated'),
    ]
    GENDER_CHOICES = [
        ('male', 'Male'),
        ('female', 'Female'),
    ]
    
    name = models.CharField(max_length=150)
    father_name = models.CharField(max_length=150)
    father_cnic = models.CharField(max_length=15, help_text="35202-XXXXXXX-X")
    parent_mobile = models.CharField(max_length=15)
    grade = models.CharField(max_length=50)
    section = models.CharField(max_length=50)
    admission_date = models.DateField(default=timezone.now)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    gender = models.CharField(max_length=10, choices=GENDER_CHOICES, blank=True, null=True)
    date_of_birth = models.DateField(blank=True, null=True)
    address = models.TextField(blank=True, null=True)
    photo = models.ImageField(upload_to="student_photos/", blank=True, null=True)
    notes = models.TextField(blank=True, null=True)
    roll_number = models.CharField(max_length=50, unique=True, blank=True)
    custom_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    enrolled_on = models.DateTimeField(auto_now_add=True)

    def save(self, *args, **kwargs):
        if not self.roll_number:
            last = Student.objects.order_by('id').last()
            if last and last.roll_number and last.roll_number.isdigit():
                self.roll_number = str(int(last.roll_number) + 1)
            else:
                self.roll_number = "1001"
        if not self.pk or self.custom_fee == 0:
            base = FeeStructure.objects.filter(grade=self.grade).first()
            if base:
                self.custom_fee = base.monthly_fee
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} ({self.roll_number})"

# ------------------- Fee Structure -------------------
class FeeStructure(models.Model):
    grade = models.CharField(max_length=50, unique=True)
    monthly_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.grade} - ₹{self.monthly_fee}"

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        Student.objects.filter(grade=self.grade).update(custom_fee=self.monthly_fee)

# ------------------- Fee Record (Monthly) -------------------
class FeeRecord(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('partial', 'Partially Paid'),
        ('paid', 'Paid'),
        ('overdue', 'Overdue'),
        ('waived', 'Waived'),
    ]
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='fee_records')
    month = models.PositiveSmallIntegerField()
    year = models.PositiveSmallIntegerField()
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    paid_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    due_date = models.DateField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    remarks = models.TextField(blank=True, null=True)

    class Meta:
        unique_together = ['student', 'month', 'year']
        ordering = ['-year', '-month']

    @property
    def remaining(self):
        return self.amount - self.paid_amount

    @property
    def is_fully_paid(self):
        return self.paid_amount >= self.amount

    def save(self, *args, **kwargs):
        if self.paid_amount >= self.amount:
            self.status = 'paid'
        elif self.paid_amount > 0:
            self.status = 'partial'
        elif date.today() > self.due_date and self.paid_amount == 0:
            self.status = 'overdue'
        else:
            self.status = 'pending'
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.student.name} - {self.month}/{self.year} - {self.get_status_display()}"

# ------------------- Payment Transaction -------------------
class PaymentTransaction(models.Model):
    PAYMENT_MODE_CHOICES = [
        ('cash', 'Cash'),
        ('bank_transfer', 'Bank Transfer'),
        ('cheque', 'Cheque'),
        ('online', 'Online'),
    ]
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='payments')
    fee_records = models.ManyToManyField(FeeRecord, related_name='payments')
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    payment_date = models.DateField(auto_now_add=True)
    payment_mode = models.CharField(max_length=20, choices=PAYMENT_MODE_CHOICES, default='cash')
    payment_type = models.CharField(max_length=20, default='full')
    receipt_number = models.CharField(max_length=50, unique=True, blank=True)
    remarks = models.TextField(blank=True, null=True)
    created_by = models.CharField(max_length=150, blank=True)

    def save(self, *args, **kwargs):
        if not self.receipt_number:
            today = date.today()
            prefix = f"RCPT-{today.strftime('%Y%m%d')}"
            last = PaymentTransaction.objects.filter(receipt_number__startswith=prefix).count()
            self.receipt_number = f"{prefix}-{last+1:04d}"
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.receipt_number} - {self.student.name} - ₹{self.amount}"

# ------------------- School Fee Settings -------------------
class SchoolFeeSettings(models.Model):
    fee_generation_day = models.PositiveSmallIntegerField(default=1, help_text="Day of month (1-31)")
    due_date_offset = models.PositiveSmallIntegerField(default=15, help_text="Days after generation when fee is due")
    late_fee_penalty = models.DecimalField(max_digits=5, decimal_places=2, default=0.00, help_text="Penalty %")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return "Fee Settings"

    class Meta:
        verbose_name_plural = "Fee Settings"

# ------------------- Gym Models -------------------
class GymCustomer(models.Model):
    STATUS_CHOICES = [
        ('active', 'Active'),
        ('expired', 'Expired'),
        ('suspended', 'Suspended'),
    ]
    GENDER_CHOICES = [
        ('male', 'Male'),
        ('female', 'Female'),
    ]
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=15)
    email = models.EmailField(blank=True, null=True)
    address = models.TextField(blank=True, null=True)
    gender = models.CharField(max_length=10, choices=GENDER_CHOICES, blank=True, null=True)
    date_of_birth = models.DateField(blank=True, null=True)
    photo = models.ImageField(upload_to='gym_customers/', blank=True, null=True)
    membership_start = models.DateField(default=timezone.now)
    membership_end = models.DateField(blank=True, null=True)
    monthly_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    notes = models.TextField(blank=True, null=True)
    created_on = models.DateTimeField(auto_now_add=True)

    def save(self, *args, **kwargs):
        if self.monthly_fee == 0:
            settings = GymSettings.objects.first()
            if settings:
                self.monthly_fee = settings.default_monthly_fee
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} ({self.phone})"

class GymSubscription(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('partial', 'Partially Paid'),
        ('paid', 'Paid'),
        ('overdue', 'Overdue'),
    ]
    customer = models.ForeignKey(GymCustomer, on_delete=models.CASCADE, related_name='subscriptions')
    month = models.PositiveSmallIntegerField()
    year = models.PositiveSmallIntegerField()
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    paid_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    due_date = models.DateField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    remarks = models.TextField(blank=True, null=True)
    # new fields for multi-month & cancellation
    is_cancelled = models.BooleanField(default=False)
    cancelled_on = models.DateField(blank=True, null=True)

    class Meta:
        unique_together = ['customer', 'month', 'year']
        ordering = ['-year', '-month']

    @property
    def remaining(self):
        return self.amount - self.paid_amount

    @property
    def is_fully_paid(self):
        return self.paid_amount >= self.amount

    def save(self, *args, **kwargs):
        if self.paid_amount >= self.amount:
            self.status = 'paid'
        elif self.paid_amount > 0:
            self.status = 'partial'
        elif date.today() > self.due_date and self.paid_amount == 0:
            self.status = 'overdue'
        else:
            self.status = 'pending'
        super().save(*args, **kwargs)

    def __str__(self):
        cancel = " [CANCELLED]" if self.is_cancelled else ""
        return f"{self.customer.name} - {self.month}/{self.year} - {self.get_status_display()}{cancel}"

class GymPayment(models.Model):
    PAYMENT_MODE_CHOICES = [
        ('cash', 'Cash'),
        ('bank_transfer', 'Bank Transfer'),
        ('cheque', 'Cheque'),
        ('online', 'Online'),
    ]
    customer = models.ForeignKey(GymCustomer, on_delete=models.CASCADE, related_name='payments')
    subscriptions = models.ManyToManyField(GymSubscription, related_name='payments')
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    payment_date = models.DateField(auto_now_add=True)
    payment_mode = models.CharField(max_length=20, choices=PAYMENT_MODE_CHOICES, default='cash')
    payment_type = models.CharField(max_length=20, default='full')
    receipt_number = models.CharField(max_length=50, unique=True, blank=True)
    remarks = models.TextField(blank=True, null=True)
    created_by = models.CharField(max_length=150, blank=True)

    def save(self, *args, **kwargs):
        if not self.receipt_number:
            today = date.today()
            prefix = f"GYM-{today.strftime('%Y%m%d')}"
            last = GymPayment.objects.filter(receipt_number__startswith=prefix).count()
            self.receipt_number = f"{prefix}-{last+1:04d}"
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.receipt_number} - {self.customer.name} - ₹{self.amount}"

class GymAttendance(models.Model):
    customer = models.ForeignKey(GymCustomer, on_delete=models.CASCADE, related_name='attendances')
    date = models.DateField(default=date.today)
    check_in = models.DateTimeField(default=timezone.now)
    check_out = models.DateTimeField(blank=True, null=True)
    notes = models.TextField(blank=True, null=True)
    updated_at = models.DateTimeField(auto_now=True)   # for edit window

    class Meta:
        unique_together = ['customer', 'date']
        ordering = ['-date', '-check_in']

    def is_editable(self):
        """Can edit within 7 hours of check-in or check-out (whichever is later)"""
        from django.utils import timezone
        now = timezone.now()
        latest = self.check_out or self.check_in
        if not latest:
            return True
        diff = now - latest
        return diff.total_seconds() <= 7 * 3600

    def __str__(self):
        return f"{self.customer.name} - {self.date} - IN:{self.check_in.strftime('%H:%M') if self.check_in else '--'}"

class GymSettings(models.Model):
    default_monthly_fee = models.DecimalField(max_digits=10, decimal_places=2, default=500.00)
    subscription_generation_day = models.PositiveSmallIntegerField(default=1)
    due_date_offset = models.PositiveSmallIntegerField(default=15)
    late_fee_penalty = models.DecimalField(max_digits=5, decimal_places=2, default=0.00)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return "Gym Settings"

    class Meta:
        verbose_name_plural = "Gym Settings"
