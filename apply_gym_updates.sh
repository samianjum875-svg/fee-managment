#!/bin/bash
# AXIS Gym Enhancement Patcher
# Run this script from your project root (where manage.py resides)

set -e

echo "📦 Applying Gym subscription & attendance updates..."

# ----------------------------------------------------------------------
# 1. Update models.py (add is_cancelled, cancelled_on to GymSubscription)
# ----------------------------------------------------------------------
cat > axis_saas/models.py << 'EOF'
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
    check_in = models.DateTimeField(auto_now_add=True)
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
EOF

# ----------------------------------------------------------------------
# 2. Create migration for new fields
# ----------------------------------------------------------------------
cat > axis_saas/migrations/0005_gym_subscription_cancel_fields.py << 'EOF'
# Generated migration for GymSubscription fields
from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [
        ('axis_saas', '0004_add_tenant_type_and_gym_models'),
    ]

    operations = [
        migrations.AddField(
            model_name='gymsubscription',
            name='is_cancelled',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='gymsubscription',
            name='cancelled_on',
            field=models.DateField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='gymattendance',
            name='updated_at',
            field=models.DateTimeField(auto_now=True),
        ),
    ]
EOF

# ----------------------------------------------------------------------
# 3. Update forms.py
# ----------------------------------------------------------------------
cat > axis_saas/forms.py << 'EOF'
from django import forms
from .models import Student, FeeStructure, PaymentTransaction, SchoolFeeSettings, GymCustomer, GymAttendance

class StudentForm(forms.ModelForm):
    class Meta:
        model = Student
        fields = ['name', 'father_name', 'father_cnic', 'parent_mobile', 'grade', 'section',
                  'admission_date', 'status', 'gender', 'date_of_birth', 'address', 'notes', 'custom_fee']
        widgets = {
            'admission_date': forms.DateInput(attrs={'type': 'date'}),
            'date_of_birth': forms.DateInput(attrs={'type': 'date'}),
            'address': forms.Textarea(attrs={'rows': 2}),
        }

class FeeCollectionForm(forms.Form):
    student = forms.ModelChoiceField(queryset=Student.objects.none(), label="Student")
    amount = forms.DecimalField(max_digits=10, decimal_places=2, label="Amount (₹)")
    payment_mode = forms.ChoiceField(choices=PaymentTransaction.PAYMENT_MODE_CHOICES, label="Payment Mode")
    remarks = forms.CharField(required=False, widget=forms.Textarea(attrs={'rows': 2}), label="Remarks")

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['student'].queryset = Student.objects.all()

class FeeStructureForm(forms.ModelForm):
    class Meta:
        model = FeeStructure
        fields = ['grade', 'monthly_fee']
        widgets = {
            'grade': forms.TextInput(attrs={'class': 'form-control'}),
            'monthly_fee': forms.NumberInput(attrs={'class': 'form-control', 'step': '0.01'}),
        }

class FeeSettingsForm(forms.ModelForm):
    class Meta:
        model = SchoolFeeSettings
        fields = ['fee_generation_day', 'due_date_offset', 'late_fee_penalty']
        widgets = {
            'fee_generation_day': forms.NumberInput(attrs={'min': 1, 'max': 31}),
            'due_date_offset': forms.NumberInput(attrs={'min': 1}),
            'late_fee_penalty': forms.NumberInput(attrs={'step': '0.01'}),
        }

class FamilyPaymentForm(forms.Form):
    father_cnic = forms.CharField(max_length=15, label="Father CNIC")
    amount = forms.DecimalField(max_digits=10, decimal_places=2, required=False, label="Amount (leave empty for full)")
    payment_mode = forms.ChoiceField(choices=PaymentTransaction.PAYMENT_MODE_CHOICES, label="Payment Mode")
    remarks = forms.CharField(required=False, widget=forms.Textarea(attrs={'rows': 2}), label="Remarks")


# ------------------- Gym Forms -------------------
class GymCustomerForm(forms.ModelForm):
    class Meta:
        from .models import GymCustomer
        model = GymCustomer
        fields = ['name', 'phone', 'email', 'address', 'gender', 'date_of_birth',
                  'membership_start', 'membership_end', 'monthly_fee', 'status', 'notes', 'photo']
        widgets = {
            'date_of_birth': forms.DateInput(attrs={'type': 'date'}),
            'membership_start': forms.DateInput(attrs={'type': 'date'}),
            'membership_end': forms.DateInput(attrs={'type': 'date'}),
            'address': forms.Textarea(attrs={'rows': 2}),
        }

class GymAttendanceForm(forms.Form):
    customer = forms.ModelChoiceField(queryset=None, label="Customer")
    check_out = forms.DateTimeField(required=False, widget=forms.DateTimeInput(attrs={'type': 'datetime-local'}))
    notes = forms.CharField(required=False, widget=forms.Textarea(attrs={'rows': 2}))

    def __init__(self, *args, **kwargs):
        from .models import GymCustomer
        super().__init__(*args, **kwargs)
        self.fields['customer'].queryset = GymCustomer.objects.filter(status='active')

class GymPaymentForm(forms.Form):
    customer = forms.ModelChoiceField(queryset=None, label="Customer")
    amount = forms.DecimalField(max_digits=10, decimal_places=2, label="Amount (₹)")
    payment_mode = forms.ChoiceField(choices=[('cash','Cash'),('bank_transfer','Bank Transfer'),('cheque','Cheque'),('online','Online')], label="Payment Mode")
    remarks = forms.CharField(required=False, widget=forms.Textarea(attrs={'rows': 2}))

    def __init__(self, *args, **kwargs):
        from .models import GymCustomer
        super().__init__(*args, **kwargs)
        self.fields['customer'].queryset = GymCustomer.objects.filter(status='active')

class GymSettingsForm(forms.ModelForm):
    class Meta:
        from .models import GymSettings
        model = GymSettings
        fields = ['default_monthly_fee', 'subscription_generation_day', 'due_date_offset', 'late_fee_penalty']
        widgets = {
            'default_monthly_fee': forms.NumberInput(attrs={'step': '0.01'}),
            'subscription_generation_day': forms.NumberInput(attrs={'min': 1, 'max': 31}),
            'due_date_offset': forms.NumberInput(attrs={'min': 1}),
            'late_fee_penalty': forms.NumberInput(attrs={'step': '0.01'}),
        }

# Subscription generation form (no model needed)
class GenerateSubscriptionForm(forms.Form):
    months = forms.ChoiceField(choices=[(1,'1 Month'),(2,'2 Months'),(3,'3 Months')], initial=1, label="Duration")
    fee = forms.DecimalField(max_digits=10, decimal_places=2, label="Monthly Fee (₹)", required=True)

# Attendance edit form
class AttendanceEditForm(forms.ModelForm):
    class Meta:
        model = GymAttendance
        fields = ['check_in', 'check_out', 'notes']
        widgets = {
            'check_in': forms.DateTimeInput(attrs={'type': 'datetime-local'}),
            'check_out': forms.DateTimeInput(attrs={'type': 'datetime-local'}),
            'notes': forms.Textarea(attrs={'rows': 2}),
        }
EOF

# ----------------------------------------------------------------------
# 4. Update views.py (add generation, cancellation, attendance edit)
# ----------------------------------------------------------------------
cat > axis_saas/views.py.new << 'EOF'
# NOTE: This is the new views.py (full replacement).
# We will concatenate with existing after the original content? Actually we must replace entire views.py.
# We'll output a complete views.py with all existing functions plus new ones.
EOF
# Since views.py is long, we'll append new functions to existing content via patching.
# Instead of rewriting, we'll add code snippets at the end.
# But easier: we can copy entire existing views.py and then append new views.
# Let's fetch existing views.py content from user (we have it). We'll produce final views.py by concatenating.
# For brevity, we'll produce a patch that adds new functions after existing ones.
# We'll use sed to insert after a marker.

# First, get existing views.py without the tail part.
cp axis_saas/views.py axis_saas/views.py.bak
# We'll insert new functions before the final `gym_receipt` definition.
# We'll create a temporary file with new content and then merge.

cat >> axis_saas/views.py << 'EOF'

# ========== GYM SUBSCRIPTION GENERATION ==========
def gym_generate_subscription(request, schema_name, customer_id):
    """Generate subscription for current month with optional multi-month"""
    from django.http import JsonResponse
    from django.views.decorators.csrf import csrf_exempt
    from .models import GymCustomer, GymSubscription, GymSettings
    from .forms import GenerateSubscriptionForm
    from datetime import date, timedelta
    from calendar import monthrange
    import json

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)
    
    try:
        data = json.loads(request.body)
    except:
        data = request.POST

    months = int(data.get('months', 1))
    custom_fee = data.get('fee')
    if not custom_fee:
        return JsonResponse({'error': 'Fee amount required'}, status=400)
    custom_fee = Decimal(str(custom_fee))

    if months < 1 or months > 3:
        return JsonResponse({'error': 'Months must be between 1 and 3'}, status=400)

    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        customer = get_object_or_404(GymCustomer, id=customer_id)
        settings, _ = GymSettings.objects.get_or_create(pk=1)
        today = date.today()
        # Determine first month to generate: current month if not already paid, otherwise next month
        # For simplicity, always generate from current month (can skip if already exists)
        generated = []
        skipped = []
        for i in range(months):
            gen_month = today.month + i
            gen_year = today.year
            while gen_month > 12:
                gen_month -= 12
                gen_year += 1
            # Check if subscription already exists for this month
            existing = GymSubscription.objects.filter(customer=customer, month=gen_month, year=gen_year).first()
            if existing and existing.is_fully_paid:
                skipped.append(f"{gen_month}/{gen_year}")
                continue
            elif existing and not existing.is_fully_paid:
                # overwrite? just update amount
                existing.amount = custom_fee
                existing.due_date = date(gen_year, gen_month, min(settings.due_date_offset, monthrange(gen_year, gen_month)[1]))
                existing.is_cancelled = False
                existing.cancelled_on = None
                existing.save()
                generated.append(f"{gen_month}/{gen_year} (updated)")
            else:
                # create new
                due_day = min(settings.due_date_offset, monthrange(gen_year, gen_month)[1])
                due_date = date(gen_year, gen_month, due_day)
                GymSubscription.objects.create(
                    customer=customer,
                    month=gen_month,
                    year=gen_year,
                    amount=custom_fee,
                    due_date=due_date,
                    status='pending'
                )
                generated.append(f"{gen_month}/{gen_year}")
        # Update customer monthly_fee if desired
        customer.monthly_fee = custom_fee
        customer.save()
        return JsonResponse({'message': f'Subscription generated for {len(generated)} month(s): {", ".join(generated)}', 'skipped': skipped})

# ========== CANCEL SUBSCRIPTION ==========
def gym_cancel_subscription(request, schema_name, subscription_id):
    from django.http import JsonResponse
    from django.views.decorators.csrf import csrf_exempt
    from .models import GymSubscription, GymPayment
    from decimal import Decimal
    from datetime import date

    if request.method != 'POST':
        return JsonResponse({'error': 'Method not allowed'}, status=405)

    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        sub = get_object_or_404(GymSubscription, id=subscription_id)
        if sub.is_cancelled:
            return JsonResponse({'error': 'Already cancelled'}, status=400)
        if sub.status == 'paid':
            return JsonResponse({'error': 'Fully paid subscriptions cannot be cancelled'}, status=400)

        # Calculate refund for current month if partially used
        today = date.today()
        # Determine number of days in month
        from calendar import monthrange
        days_in_month = monthrange(sub.year, sub.month)[1]
        # Days used = today's day number (if today <= last day of month, else full month)
        if today.year == sub.year and today.month == sub.month:
            days_used = min(today.day, days_in_month)
        else:
            # Future month - zero used
            days_used = 0
        daily_rate = sub.amount / days_in_month
        used_amount = daily_rate * days_used
        refund = sub.paid_amount - used_amount
        if refund < 0:
            refund = Decimal('0.00')

        # Update subscription
        sub.is_cancelled = True
        sub.cancelled_on = today
        # Adjust paid_amount to used_amount
        sub.paid_amount = used_amount
        sub.save()

        # If refund > 0, create a negative payment (or just record adjustment)
        if refund > 0:
            # We'll create a "refund" payment (negative amount) for audit
            GymPayment.objects.create(
                customer=sub.customer,
                amount=-refund,
                payment_mode='refund',
                payment_type='refund',
                remarks=f'Refund for cancelled subscription {sub.month}/{sub.year}',
                created_by=request.session.get('school_admin_username', 'admin')
            ).subscriptions.add(sub)

        return JsonResponse({'message': f'Subscription cancelled. Refund amount: ₹{refund}', 'refund': float(refund)})

# ========== ATTENDANCE EDIT ==========
def gym_edit_attendance(request, schema_name, attendance_id):
    from django.http import JsonResponse
    from django.views.decorators.csrf import csrf_exempt
    from .models import GymAttendance
    from .forms import AttendanceEditForm
    import json

    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        attendance = get_object_or_404(GymAttendance, id=attendance_id)
        if not attendance.is_editable():
            return JsonResponse({'error': 'Attendance record is older than 7 hours and cannot be edited'}, status=400)

        if request.method == 'POST':
            form = AttendanceEditForm(request.POST, instance=attendance)
            if form.is_valid():
                form.save()
                return JsonResponse({'message': 'Attendance updated successfully'})
            else:
                return JsonResponse({'errors': form.errors}, status=400)
        else:
            # GET: return current data
            data = {
                'check_in': attendance.check_in.isoformat() if attendance.check_in else '',
                'check_out': attendance.check_out.isoformat() if attendance.check_out else '',
                'notes': attendance.notes or '',
                'editable': attendance.is_editable()
            }
            return JsonResponse(data)

# ========== ATTENDANCE HISTORY ON CUSTOMER PROFILE ==========
# Add attendance data to gym_customer_profile context
# We'll override the existing gym_customer_profile view to include attendance history.
# Since we already have that view in views.py, we'll add lines there.
# We'll patch that function.
EOF

# Now we need to modify existing gym_customer_profile view to include attendance. Let's patch it.
# We'll use sed to add one line inside the context building.
# But easier: we'll replace the whole gym_customer_profile function with an updated version.
# We'll create a small patch script.

cat > /tmp/patch_gym_profile.py << 'PYEOF'
import re, sys
with open('axis_saas/views.py', 'r') as f:
    content = f.read()

# Find gym_customer_profile function and replace its context building part
new_profile_func = '''def gym_customer_profile(request, schema_name, customer_id):
    tenant = get_tenant(request, schema_name)
    from .models import GymCustomer, GymSubscription, GymPayment, GymAttendance
    from datetime import date, timedelta
    with schema_context(schema_name):
        customer = get_object_or_404(GymCustomer, id=customer_id)
        subscriptions = customer.subscriptions.all().order_by('-year', '-month')
        payments = customer.payments.all().order_by('-payment_date')
        attendances = customer.attendances.all().order_by('-date')  # add attendance
        total_fee = subscriptions.aggregate(Sum('amount'))['amount__sum'] or 0
        total_paid = payments.aggregate(Sum('amount'))['amount__sum'] or 0
        pending_total = total_fee - total_paid
        # Add editable flag to each attendance
        for a in attendances:
            a.can_edit = a.is_editable()
        context = {
            'tenant': tenant, 'customer': customer, 'subscriptions': subscriptions, 'payments': payments,
            'total_fee': total_fee, 'total_paid': total_paid, 'pending_total': pending_total,
            'attendances': attendances,  # new
            'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        }
    return render(request, 'tenant/gym_customer_profile.html', context)'''

# Replace function definition using regex
pattern = r'def gym_customer_profile\(request, schema_name, customer_id\):.*?(?=\n\ndef|\Z)'
content = re.sub(pattern, new_profile_func, content, flags=re.DOTALL)
with open('axis_saas/views.py', 'w') as f:
    f.write(content)
print("Patched gym_customer_profile to include attendance history.")
PYEOF

python3 /tmp/patch_gym_profile.py

# ----------------------------------------------------------------------
# 5. Update URLs (public_urls.py)
# ----------------------------------------------------------------------
cat >> axis_saas/public_urls.py << 'EOF'
    # New gym subscription & cancellation routes
    path('portal/<slug:schema_name>/gym/customers/<int:customer_id>/generate-subscription/', gym_generate_subscription, name='gym_generate_subscription'),
    path('portal/<slug:schema_name>/gym/subscriptions/<int:subscription_id>/cancel/', gym_cancel_subscription, name='gym_cancel_subscription'),
    path('portal/<slug:schema_name>/gym/attendance/<int:attendance_id>/edit/', gym_edit_attendance, name='gym_edit_attendance'),
EOF

# Also need to import new functions in public_urls.py
sed -i 's/from .views import /from .views import gym_generate_subscription, gym_cancel_subscription, gym_edit_attendance, /' axis_saas/public_urls.py

# ----------------------------------------------------------------------
# 6. Overwrite gym_customer_profile.html with subscription button + attendance history
# ----------------------------------------------------------------------
cat > templates/tenant/gym_customer_profile.html << 'EOF'
{% extends 'tenant/base.html' %}
{% block title %}{{ customer.name }} Profile{% endblock %}
{% block body %}
<div class="profile-header">
    <div><h1 class="page-title">{{ customer.name }}</h1><p class="page-desc">{{ customer.phone }} • {{ customer.email|default:"No email" }}</p></div>
    <div class="header-actions">
        <a href="{% url 'gym_customer_edit' schema_name=tenant.schema_name customer_id=customer.id %}" class="btn-secondary">✏️ Edit</a>
        <button id="generateSubscriptionBtn" class="btn-primary">📅 Generate Subscription</button>
        <a href="{% url 'gym_payment' schema_name=tenant.schema_name customer_id=customer.id %}" class="btn-primary">💰 Collect Payment</a>
        <a href="{% url 'gym_customer_list' schema_name=tenant.schema_name %}" class="btn-secondary">← Back</a>
    </div>
</div>

<div class="info-grid">
    <div class="info-card"><div class="info-label">Membership</div><div class="info-value">{{ customer.membership_start|date:"Y-m-d" }} → {{ customer.membership_end|date:"Y-m-d"|default:"Ongoing" }}</div></div>
    <div class="info-card"><div class="info-label">Monthly Fee</div><div class="info-value">₹{{ customer.monthly_fee }}</div></div>
    <div class="info-card"><div class="info-label">Status</div><div class="info-value"><span class="status-badge status-{{ customer.status }}">{{ customer.get_status_display }}</span></div></div>
</div>

<div class="fee-summary">
    <div class="summary-card"><div class="summary-label">Total Billed</div><div class="summary-value">₹{{ total_fee|floatformat:2 }}</div></div>
    <div class="summary-card"><div class="summary-label">Total Paid</div><div class="summary-value">₹{{ total_paid|floatformat:2 }}</div></div>
    <div class="summary-card"><div class="summary-label">Pending</div><div class="summary-value pending">₹{{ pending_total|floatformat:2 }}</div></div>
</div>

<!-- Subscription Table -->
<div class="table-card">
    <h3>Subscription History</h3>
    <div class="table-responsive">
        <table class="data-table" id="subscriptionsTable">
            <thead>
                <tr><th>Month/Year</th><th>Amount</th><th>Paid</th><th>Status</th><th>Action</th><th>Receipts</th></tr>
            </thead>
            <tbody>
                {% for s in subscriptions %}
                <td>
                    <td>{{ s.month }}/{{ s.year }}</td>
                    <td>₹{{ s.amount }}</td>
                    <td>₹{{ s.paid_amount }}</td>
                    <td>{{ s.get_status_display }}{% if s.is_cancelled %} (Cancelled){% endif %}</td>
                    <td>{% if not s.is_cancelled and s.status != 'paid' %}<button class="cancel-sub-btn" data-id="{{ s.id }}">Cancel</button>{% endif %}</td>
                    <td>{% for p in s.payments.all %}<a href="{% url 'gym_receipt' schema_name=tenant.schema_name receipt_id=p.id %}">{{ p.receipt_number }}</a> {% endfor %}</td>
                </tr>
                {% empty %}
                <tr><td colspan="6">No subscriptions</td></tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>

<!-- Payment History Table -->
<div class="table-card">
    <h3>Payment History</h3>
    <div class="table-responsive">
        <table class="data-table">
            <thead>
                <tr><th>Receipt</th><th>Amount</th><th>Date</th><th>Mode</th></tr>
            </thead>
            <tbody>
                {% for p in payments %}
                <tr><td><a href="{% url 'gym_receipt' schema_name=tenant.schema_name receipt_id=p.id %}">{{ p.receipt_number }}</a></td><td>₹{{ p.amount }}</td><td>{{ p.payment_date|date:"Y-m-d" }}</td><td>{{ p.get_payment_mode_display }}</td></tr>
                {% empty %}<tr><td colspan="4">No payments</td></tr>{% endfor %}
            </tbody>
        </table>
    </div>
</div>

<!-- Attendance History -->
<div class="table-card">
    <h3>Attendance History</h3>
    <div class="table-responsive">
        <table class="data-table" id="attendanceTable">
            <thead>
                <tr><th>Date</th><th>Check In</th><th>Check Out</th><th>Notes</th><th>Actions</th></tr>
            </thead>
            <tbody>
                {% for a in attendances %}
                <tr data-att-id="{{ a.id }}">
                    <td>{{ a.date|date:"Y-m-d" }}</td>
                    <td>{{ a.check_in|date:"Y-m-d H:i" }}</td>
                    <td>{{ a.check_out|date:"Y-m-d H:i"|default:"-" }}</td>
                    <td>{{ a.notes|default:"-" }}</td>
                    <td>{% if a.can_edit %}<button class="edit-att-btn" data-id="{{ a.id }}">Edit</button>{% else %}Locked{% endif %}</td>
                </tr>
                {% empty %}
                <tr><td colspan="5">No attendance records</td></tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>

<!-- Subscription Generation Modal -->
<div id="subModal" class="modal" style="display:none;">
    <div class="modal-content">
        <span class="close">&times;</span>
        <h3>Generate Subscription</h3>
        <form id="subForm">
            {% csrf_token %}
            <label>Months (1-3):</label>
            <select name="months" id="monthsSelect">
                <option value="1">1 Month</option>
                <option value="2">2 Months</option>
                <option value="3">3 Months</option>
            </select>
            <label>Monthly Fee (₹):</label>
            <input type="number" step="0.01" name="fee" id="feeInput" value="{{ customer.monthly_fee }}" required>
            <button type="submit" id="confirmGenBtn">Generate</button>
        </form>
    </div>
</div>

<!-- Attendance Edit Modal -->
<div id="attEditModal" class="modal" style="display:none;">
    <div class="modal-content">
        <span class="close">&times;</span>
        <h3>Edit Attendance</h3>
        <form id="attEditForm">
            {% csrf_token %}
            <label>Check In:</label>
            <input type="datetime-local" name="check_in" id="editCheckIn" required>
            <label>Check Out:</label>
            <input type="datetime-local" name="check_out" id="editCheckOut">
            <label>Notes:</label>
            <textarea name="notes" id="editNotes" rows="2"></textarea>
            <button type="submit">Save Changes</button>
        </form>
    </div>
</div>

<style>
.modal { position: fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); display:flex; align-items:center; justify-content:center; z-index:1000; }
.modal-content { background: var(--surface); border-radius: var(--radius); padding: 1.5rem; min-width: 300px; box-shadow: var(--shadow); }
.modal-content .close { float:right; cursor:pointer; font-size:1.5rem; }
.modal-content form { display:flex; flex-direction:column; gap:1rem; margin-top:1rem; }
.modal-content label { font-weight:600; }
.modal-content input, .modal-content select, .modal-content textarea { padding:0.5rem; border-radius:0.5rem; border:1px solid var(--border); background: var(--surface-alt); }
.btn-primary, .btn-secondary, button { background: var(--primary); color:white; border:none; border-radius:2rem; padding:0.3rem 1rem; cursor:pointer; }
.cancel-sub-btn { background: var(--danger); }
.edit-att-btn { background: var(--primary); }
</style>

<script>
function getCookie(name) {
    let cookieValue = null;
    if (document.cookie && document.cookie !== '') {
        const cookies = document.cookie.split(';');
        for (let i = 0; i < cookies.length; i++) {
            const cookie = cookies[i].trim();
            if (cookie.substring(0, name.length + 1) === (name + '=')) {
                cookieValue = decodeURIComponent(cookie.substring(name.length + 1));
                break;
            }
        }
    }
    return cookieValue;
}
const csrftoken = getCookie('csrftoken');
const schema = "{{ tenant.schema_name }}";
const customerId = {{ customer.id }};

// Generation modal
const modal = document.getElementById('subModal');
const genBtn = document.getElementById('generateSubscriptionBtn');
const span = modal.querySelector('.close');
genBtn.onclick = () => modal.style.display = 'flex';
span.onclick = () => modal.style.display = 'none';
window.onclick = (e) => { if (e.target == modal) modal.style.display = 'none'; };

document.getElementById('subForm').onsubmit = async (e) => {
    e.preventDefault();
    const months = document.getElementById('monthsSelect').value;
    const fee = document.getElementById('feeInput').value;
    const btn = document.getElementById('confirmGenBtn');
    btn.disabled = true;
    btn.innerText = 'Generating...';
    try {
        const resp = await fetch(`/portal/${schema}/gym/customers/${customerId}/generate-subscription/`, {
            method: 'POST',
            headers: { 'X-CSRFToken': csrftoken, 'Content-Type': 'application/json' },
            body: JSON.stringify({ months: parseInt(months), fee: fee })
        });
        const data = await resp.json();
        alert(data.message || data.error);
        if (!data.error) location.reload();
    } catch(e) { alert('Error: ' + e.message); }
    finally { btn.disabled = false; btn.innerText = 'Generate'; modal.style.display = 'none'; }
};

// Cancel subscription
document.querySelectorAll('.cancel-sub-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
        const subId = btn.dataset.id;
        if (!confirm('Cancel this subscription? Partial refund will be calculated.')) return;
        btn.disabled = true;
        btn.innerText = '...';
        try {
            const resp = await fetch(`/portal/${schema}/gym/subscriptions/${subId}/cancel/`, {
                method: 'POST',
                headers: { 'X-CSRFToken': csrftoken }
            });
            const data = await resp.json();
            alert(data.message);
            if (!data.error) location.reload();
        } catch(e) { alert('Error: ' + e.message); }
        finally { btn.disabled = false; }
    });
});

// Attendance edit modal
const attModal = document.getElementById('attEditModal');
let currentAttId = null;
document.querySelectorAll('.edit-att-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
        currentAttId = btn.dataset.id;
        // fetch current data
        const resp = await fetch(`/portal/${schema}/gym/attendance/${currentAttId}/edit/`);
        const data = await resp.json();
        if (data.error) { alert(data.error); return; }
        document.getElementById('editCheckIn').value = data.check_in.slice(0,16);
        document.getElementById('editCheckOut').value = data.check_out ? data.check_out.slice(0,16) : '';
        document.getElementById('editNotes').value = data.notes;
        attModal.style.display = 'flex';
    });
});
attModal.querySelector('.close').onclick = () => attModal.style.display = 'none';
document.getElementById('attEditForm').onsubmit = async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const btn = attModal.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
        const resp = await fetch(`/portal/${schema}/gym/attendance/${currentAttId}/edit/`, {
            method: 'POST',
            headers: { 'X-CSRFToken': csrftoken },
            body: formData
        });
        const data = await resp.json();
        if (data.message) alert(data.message);
        else if (data.errors) alert('Error: ' + JSON.stringify(data.errors));
        if (!data.error) location.reload();
    } catch(e) { alert('Error: ' + e.message); }
    finally { btn.disabled = false; attModal.style.display = 'none'; }
};
</script>
{% endblock %}
EOF

# ----------------------------------------------------------------------
# 7. Overwrite gym_attendance.html with cleaner version (7‑hour edit)
# ----------------------------------------------------------------------
cat > templates/tenant/gym_attendance.html << 'EOF'
{% extends 'tenant/base.html' %}
{% block title %}Attendance | {{ tenant.name }}{% endblock %}
{% block body %}
<div class="page-header">
    <div><h1 class="page-title">Daily Attendance</h1><p class="page-desc">Check-in / Check-out members (editable within 7 hours)</p></div>
    <div class="header-stats"><div class="stat-badge"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"><circle cx="12" cy="12" r="10"/><path d="M12 8v4l3 3"/></svg><span>Today: <strong>{{ checkins_today|length }}</strong> check-ins</span></div><button id="refreshBtn" class="btn-refresh">⟳ Refresh</button></div>
</div>

<div class="checkin-card">
    <div class="card-header"><h3>Quick Check-in</h3></div>
    <form method="post" class="checkin-form" id="checkinForm">
        {% csrf_token %}
        <div class="form-row">
            <div class="form-field"><label>Customer</label><div class="searchable-dropdown"><input type="text" id="customerSearch" placeholder="Type to search..." class="search-input"><select name="customer" id="customerSelect" style="display:none;">{{ form.customer }}</select></div></div>
            <div class="form-field"><label>Check-out (optional)</label>{{ form.check_out }}</div>
            <div class="form-field"><label>Notes</label>{{ form.notes }}</div>
            <div class="form-field submit-field"><button type="submit" class="btn-primary">✔ Check In</button></div>
        </div>
    </form>
</div>

<div class="attendance-grid">
    <div class="attendance-card"><div class="card-header"><h3>Today's Check-ins</h3><div class="search-wrapper"><input type="text" id="todaySearch" placeholder="Search..." class="table-search"></div></div>
        <div class="table-responsive"><table class="data-table" id="todayTable"><thead><tr><th>Customer</th><th>Check-in Time</th><th>Check-out</th><th>Action</th></tr></thead><tbody>{% for a in checkins_today %}<tr data-customer-name="{{ a.customer.name|lower }}"><td><strong>{{ a.customer.name }}</strong><br><small>{{ a.customer.phone }}</small></td><td>{{ a.check_in|time:"H:i" }}</td><td>{% if a.check_out %}{{ a.check_out|time:"H:i" }}{% else %}—{% endif %}</td><td>{% if not a.check_out %}<button class="btn-checkout" data-id="{{ a.customer.id }}">Check-out</button>{% endif %}</td></tr>{% empty %}<tr><td colspan="4">No check-ins today</td></tr>{% endfor %}</tbody></table></div>
    </div>
    <div class="attendance-card"><div class="card-header"><h3>Last 7 Days Attendance</h3><div class="search-wrapper"><input type="text" id="recentSearch" placeholder="Search..." class="table-search"></div></div>
        <div class="table-responsive"><table class="data-table" id="recentTable"><thead><tr><th>Date</th><th>Customer</th><th>Check-in</th><th>Check-out</th><th>Edit</th></tr></thead><tbody>{% for a in recent_attendance %}<tr data-customer-name="{{ a.customer.name|lower }}"><td>{{ a.date|date:"Y-m-d" }}</td><td><strong>{{ a.customer.name }}</strong><br><small>{{ a.customer.phone }}</small></td><td>{{ a.check_in|time:"H:i" }}</td><td>{{ a.check_out|time:"H:i"|default:"-" }}</td><td>{% if a.is_editable %}<button class="edit-att-btn" data-id="{{ a.id }}">Edit</button>{% else %}Locked{% endif %}</td></tr>{% empty %}<tr><td colspan="5">No recent attendance</td></tr>{% endfor %}</tbody></table></div>
    </div>
</div>

<div class="chart-card"><canvas id="attendanceTrend" height="100"></canvas></div>

<!-- Attendance Edit Modal -->
<div id="attEditModal" class="modal" style="display:none;"><div class="modal-content"><span class="close">&times;</span><h3>Edit Attendance</h3><form id="attEditForm">{% csrf_token %}<label>Check In:</label><input type="datetime-local" name="check_in" id="editCheckIn" required><label>Check Out:</label><input type="datetime-local" name="check_out" id="editCheckOut"><label>Notes:</label><textarea name="notes" id="editNotes" rows="2"></textarea><button type="submit">Save</button></form></div></div>

<style>
.modal { position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); display:flex; align-items:center; justify-content:center; z-index:1000; }
.modal-content { background: var(--surface); border-radius: var(--radius); padding:1.5rem; min-width:300px; }
.modal-content .close { float:right; cursor:pointer; font-size:1.5rem; }
.modal-content form { display:flex; flex-direction:column; gap:1rem; margin-top:1rem; }
.modal-content label { font-weight:600; }
.modal-content input, .modal-content textarea { padding:0.5rem; border-radius:0.5rem; border:1px solid var(--border); background: var(--surface-alt); }
.btn-checkout { background: var(--danger); color:white; border:none; border-radius:2rem; padding:0.2rem 0.8rem; cursor:pointer; }
.edit-att-btn { background: var(--primary); color:white; border:none; border-radius:2rem; padding:0.2rem 0.8rem; cursor:pointer; }
</style>

<script>
function getCookie(name){let v=null;if(document.cookie&&document.cookie!==''){const c=document.cookie.split(';');for(let i=0;i<c.length;i++){const cookie=c[i].trim();if(cookie.substring(0,name.length+1)===(name+'=')){v=decodeURIComponent(cookie.substring(name.length+1));break;}}}return v;}
const csrftoken=getCookie('csrftoken');
const schema="{{ tenant.schema_name }}";

// Refresh
document.getElementById('refreshBtn').onclick=()=>location.reload();

// Customer search dropdown
const custSearch=document.getElementById('customerSearch');
const custSelect=document.getElementById('customerSelect');
if(custSearch&&custSelect){
    const options=Array.from(custSelect.options);
    const dropdown=document.createElement('div');
    dropdown.className='customer-select';
    dropdown.style.display='none';
    custSearch.parentNode.appendChild(dropdown);
    function updateDropdown(filter=''){
        dropdown.innerHTML='';
        const filtered=options.filter(opt=>opt.text.toLowerCase().includes(filter.toLowerCase())&&opt.value);
        if(filtered.length===0){const no=document.createElement('div');no.textContent='No customers';no.style.padding='0.5rem';dropdown.appendChild(no);}
        else filtered.forEach(opt=>{const item=document.createElement('div');item.textContent=opt.text;item.style.padding='0.5rem';item.style.cursor='pointer';item.onclick=()=>{custSearch.value=opt.text;custSelect.value=opt.value;dropdown.style.display='none';};dropdown.appendChild(item);});
        dropdown.style.display='block';
    }
    custSearch.addEventListener('input',e=>updateDropdown(e.target.value));
    custSearch.addEventListener('focus',()=>updateDropdown(custSearch.value));
    document.addEventListener('click',e=>{if(!dropdown.contains(e.target)&&e.target!==custSearch)dropdown.style.display='none';});
    document.getElementById('checkinForm').addEventListener('submit',e=>{if(!custSelect.value&&custSearch.value){const match=options.find(opt=>opt.text===custSearch.value);if(match)custSelect.value=match.value;else{e.preventDefault();alert('Select valid customer');}}});
}

// Checkout
document.querySelectorAll('.btn-checkout').forEach(btn=>btn.addEventListener('click',async function(){const id=this.dataset.id;if(!confirm('Check out?'))return;this.disabled=true;this.innerText='...';try{const resp=await fetch('/api/gym/checkout/',{method:'POST',headers:{'X-CSRFToken':csrftoken,'Content-Type':'application/x-www-form-urlencoded'},body:`customer_id=${id}`});const data=await resp.json();alert(data.message);location.reload();}catch(e){alert(e.message);this.disabled=false;this.innerText='Check-out';}}));

// Table search
document.getElementById('todaySearch')?.addEventListener('keyup',function(){const filter=this.value.toLowerCase();document.querySelectorAll('#todayTable tbody tr').forEach(row=>{const name=row.getAttribute('data-customer-name')||'';row.style.display=name.includes(filter)?'':'none';});});
document.getElementById('recentSearch')?.addEventListener('keyup',function(){const filter=this.value.toLowerCase();document.querySelectorAll('#recentTable tbody tr').forEach(row=>{const name=row.getAttribute('data-customer-name')||'';row.style.display=name.includes(filter)?'':'none';});});

// Attendance edit modal
const attModal=document.getElementById('attEditModal');
let currentAttId=null;
document.querySelectorAll('.edit-att-btn').forEach(btn=>btn.addEventListener('click',async function(){currentAttId=this.dataset.id;const resp=await fetch(`/portal/${schema}/gym/attendance/${currentAttId}/edit/`);const data=await resp.json();if(data.error)alert(data.error);else{document.getElementById('editCheckIn').value=data.check_in.slice(0,16);document.getElementById('editCheckOut').value=data.check_out?data.check_out.slice(0,16):'';document.getElementById('editNotes').value=data.notes;attModal.style.display='flex';}}));
attModal.querySelector('.close').onclick=()=>attModal.style.display='none';
document.getElementById('attEditForm').onsubmit=async(e)=>{e.preventDefault();const formData=new FormData(e.target);const btn=attModal.querySelector('button[type="submit"]');btn.disabled=true;try{const resp=await fetch(`/portal/${schema}/gym/attendance/${currentAttId}/edit/`,{method:'POST',headers:{'X-CSRFToken':csrftoken},body:formData});const data=await resp.json();if(data.message)alert(data.message);else if(data.errors)alert('Error: '+JSON.stringify(data.errors));if(!data.error)location.reload();}catch(e){alert(e.message);}finally{btn.disabled=false;attModal.style.display='none';}};

// Chart
const ctx=document.getElementById('attendanceTrend')?.getContext('2d');
if(ctx){const last7Days={};document.querySelectorAll('#recentTable tbody tr').forEach(row=>{const dateCell=row.cells[0];if(dateCell){const date=dateCell.innerText;last7Days[date]=(last7Days[date]||0)+1;}});const dates=Object.keys(last7Days).sort().slice(-7);const counts=dates.map(d=>last7Days[d]);new Chart(ctx,{type:'line',data:{labels:dates,datasets:[{label:'Check-ins',data:counts,borderColor:'#3b82f6',fill:true}]}});}
</script>
{% endblock %}
EOF

# ----------------------------------------------------------------------
# 8. Final steps
# ----------------------------------------------------------------------
echo "✅ Patches applied successfully."
echo "Now run:"
echo "  python3 manage.py makemigrations axis_saas"
echo "  python3 manage.py migrate"
echo "  python3 manage.py runserver"
EOF

# Make script executable
chmod +x apply_gym_updates.sh

echo "Patcher script generated as 'apply_gym_updates.sh'. Run it from your project root."
