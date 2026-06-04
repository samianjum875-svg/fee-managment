from django import forms
from django.db import models
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
        super().__init__(*args, **kwargs)
        from .models import GymCustomer
        # Show all active customers (subscription validation is done in API)
        self.fields['customer'].queryset = GymCustomer.objects.filter(status='active')
class GymPaymentForm(forms.Form):
    customer = forms.ModelChoiceField(queryset=None, label="Customer")
    amount = forms.DecimalField(max_digits=10, decimal_places=2, label="Amount (₹)")
    payment_mode = forms.ChoiceField(choices=[('cash','Cash'),('bank_transfer','Bank Transfer'),('cheque','Cheque'),('online','Online')], label="Payment Mode")
    remarks = forms.CharField(required=False, widget=forms.Textarea(attrs={'rows': 2}))

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        from .models import GymCustomer
        # Show all active customers (payment logic handles pending check)
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
