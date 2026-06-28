import json
from decimal import Decimal

from django.test import RequestFactory, SimpleTestCase
from django_tenants.test.cases import TenantTestCase

from axis_saas.models import FeeStructure, SchoolClient, SchoolFeeSettings, Student
from axis_saas.views import generate_voucher_api


class VoucherDefaultsTests(TenantTestCase):
    @classmethod
    def setup_tenant(cls, tenant):
        tenant.schema_name = 'voucherdefaults'
        tenant.name = 'Voucher Defaults School'
        tenant.admin_username = 'admin'
        tenant.admin_password = 'pass'
        tenant.save()

    def setUp(self):
        super().setUp()
        self.factory = RequestFactory()
        self.student = Student.objects.create(
            name='Ali Khan',
            father_name='Khan',
            father_cnic='35202-1234567-1',
            parent_mobile='03001234567',
            grade='Grade 5',
            section='A',
            roll_number='2001',
            custom_fee=Decimal('500.00'),
        )
        FeeStructure.objects.create(grade='Grade 5', monthly_fee=Decimal('500.00'))

    def test_generate_voucher_saves_global_defaults_when_requested(self):
        payload = {
            'custom_amount': '650.00',
            'charges': [{'title': 'Library Fee', 'amount': '25.00'}],
            'save_default_charges': True,
            'due_date_offset': 7,
            'late_fee_penalty': '15.00',
        }
        request = self.factory.post(
            '/fake/',
            data=json.dumps(payload),
            content_type='application/json',
        )

        response = generate_voucher_api(request, schema_name='voucherdefaults', student_id=self.student.id)

        self.assertEqual(response.status_code, 200)
        settings = SchoolFeeSettings.objects.get(pk=1)
        self.assertEqual(settings.default_extra_charges[0]['title'], 'Library Fee')
        self.assertEqual(settings.due_date_offset, 7)
        self.assertEqual(settings.late_fee_penalty, Decimal('15.00'))
