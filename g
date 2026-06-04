#!/usr/bin/env python3
"""
Patcher for gym_generate_subscription view - fixes UnboundLocalError: due_date
"""

import re
import os
import shutil
from pathlib import Path

VIEWS_FILE = Path("axis_saas/views.py")
BACKUP_SUFFIX = ".bak_gym_fix"

def patch_views():
    if not VIEWS_FILE.exists():
        print(f"❌ {VIEWS_FILE} not found. Run this script from the project root.")
        return False

    # Backup
    backup_path = VIEWS_FILE.with_suffix(VIEWS_FILE.suffix + BACKUP_SUFFIX)
    shutil.copy2(VIEWS_FILE, backup_path)
    print(f"✅ Backup created: {backup_path}")

    with open(VIEWS_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # Locate the function definition
    func_pattern = r'(def gym_generate_subscription\(request, schema_name, customer_id\):.*?)(?=\n\ndef |\n@|$)'
    match = re.search(func_pattern, content, re.DOTALL)
    if not match:
        print("❌ Could not find gym_generate_subscription function.")
        return False

    old_func = match.group(1)

    # The fixed code – we'll replace the whole function
    # I will write a corrected version by modifying the problematic part.
    # The key change: compute due_date BEFORE checking existing, so it's always available.
    fixed_func = """def gym_generate_subscription(request, schema_name, customer_id):
    \"\"\"Generate a new subscription for a gym customer (multi-month).\"\"\"
    from django.http import JsonResponse
    from django.utils import timezone
    from decimal import Decimal
    from .models import GymCustomer, GymSubscription, GymSettings
    from datetime import date, timedelta
    from calendar import monthrange
    import json
    from django_tenants.utils import schema_context
    with schema_context(schema_name):
        try:
            customer = GymCustomer.objects.get(id=customer_id)
        except GymCustomer.DoesNotExist:
            return JsonResponse({'error': 'Customer not found'}, status=404)

        if request.method != 'POST':
            return JsonResponse({'error': 'Only POST allowed'}, status=405)

        try:
            data = json.loads(request.body)
            months = int(data.get('months', 1))
            monthly_fee = Decimal(str(data.get('fee', customer.monthly_fee)))
        except (ValueError, TypeError, json.JSONDecodeError):
            return JsonResponse({'error': 'Invalid data. Provide months and fee.'}, status=400)

        if months < 1 or months > 12:
            return JsonResponse({'error': 'Months must be between 1 and 12'}, status=400)

        today = date.today()
        settings = GymSettings.objects.first()
        if not settings:
            settings = GymSettings.objects.create()
        due_offset = settings.due_date_offset

        created = []

        for i in range(months):
            target_month = today.month + i
            target_year = today.year
            while target_month > 12:
                target_month -= 12
                target_year += 1

            # ✅ Compute due_date for this target month BEFORE checking existence
            due_day = customer.membership_start.day if customer.membership_start else 1
            max_day = monthrange(target_year, target_month)[1]
            due_day = min(due_day, max_day)
            due_date = date(target_year, target_month, due_day) + timedelta(days=due_offset)

            existing = GymSubscription.objects.filter(customer=customer, month=target_month, year=target_year).first()
            if existing:
                if existing.is_cancelled:
                    # Reactivate cancelled subscription with new parameters
                    existing.amount = monthly_fee
                    existing.paid_amount = Decimal('0')
                    existing.due_date = due_date          # ✅ now due_date is defined
                    existing.status = 'pending'
                    existing.is_cancelled = False
                    existing.cancelled_on = None
                    existing.save()
                    created.append(existing)
                else:
                    # Already have a valid subscription for this month
                    continue
            else:
                # No subscription → create new one
                sub = GymSubscription.objects.create(
                    customer=customer,
                    month=target_month,
                    year=target_year,
                    amount=monthly_fee,
                    due_date=due_date,
                    status='pending'
                )
                created.append(sub)

        if created:
            return JsonResponse({'message': f'Generated {len(created)} subscription(s).'})
        else:
            return JsonResponse({'message': 'No new subscriptions created (already exist).'})
"""
    # Replace the old function with the fixed version
    new_content = content.replace(old_func, fixed_func)

    # Write back
    with open(VIEWS_FILE, "w", encoding="utf-8") as f:
        f.write(new_content)

    print("✅ Fixed gym_generate_subscription function.")
    print("   Restart your Django server to apply changes.")
    return True

if __name__ == "__main__":
    patch_views()
