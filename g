#!/usr/bin/env python3
"""
Patcher to fix the dashboard view:
- Removes duplicate code
- Defines collection_rate correctly
- Uses get_overall_pending for total_pending (same as defaulters)
Run: python3 clean_dashboard_patcher.py
"""
import os
import re
import sys

def patch_dashboard():
    views_path = "axis_saas/views.py"
    if not os.path.exists(views_path):
        print(f"❌ Error: {views_path} not found.")
        sys.exit(1)

    with open(views_path, "r") as f:
        content = f.read()

    # Locate the dashboard function – we'll replace the entire function body
    # We'll use a pattern that matches from "def dashboard(...)" to the next "def " at same indent level
    # or to the end of the function (which is a line with same or less indent that is not a continuation)
    # But easier: we'll replace everything between "def dashboard(...):" and the next "def " at top level.
    # We'll use a regex with DOTALL to capture the function.

    # Find the start of the dashboard function
    dashboard_pattern = r'(def dashboard\(request, schema_name\):.*?)(?=\n\s*def |\n\n\S)'
    match = re.search(dashboard_pattern, content, re.DOTALL)
    if not match:
        print("❌ Could not find the 'dashboard' function.")
        sys.exit(1)

    old_dashboard = match.group(1)

    # Build a new clean dashboard function
    new_dashboard = """def dashboard(request, schema_name):
    \"\"\"Enhanced school dashboard with comprehensive KPIs and quick actions.\"\"\"
    tenant = get_tenant(request, schema_name)
    with schema_context(schema_name):
        today = timezone.localdate()
        first_day_month = today.replace(day=1)

        # ---- Core financials ----
        today_collection = PaymentTransaction.objects.filter(payment_date=today).aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        month_collection = PaymentTransaction.objects.filter(payment_date__gte=first_day_month).aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        
        # Total revenue (all time)
        total_revenue = PaymentTransaction.objects.aggregate(Sum('amount'))['amount__sum'] or Decimal('0')
        
        # Total pending – overall pending (fee + items - paid) for each student
        total_pending = Decimal('0')
        for student in Student.objects.all():
            total_pending += get_overall_pending(student)
        
        # Defaulters count (students with pending/partial/overdue)
        defaulters_count = Student.objects.filter(fee_records__status__in=['pending', 'partial', 'overdue']).distinct().count()
        
        # Total students
        total_students = Student.objects.count()
        
        # Low stock items (quantity < 10)
        low_stock_count = Product.objects.filter(quantity__lt=10).count()
        
        # Collection rate
        total_billed = total_revenue + total_pending
        collection_rate = (float(total_revenue) / float(total_billed) * 100) if total_billed > 0 else 0
        
        # Recent payments (last 5)
        recent_payments = list(PaymentTransaction.objects.select_related('student').order_by('-payment_date')[:5])
        
        # Top defaulters (by pending amount)
        top_defaulters = []
        for student in Student.objects.all():
            pending = get_overall_pending(student)
            if pending > 0:
                fee_pending = sum(fr.remaining for fr in student.fee_records.filter(status__in=['pending','partial','overdue']))
                top_defaulters.append({'student': student, 'pending': pending, 'fee_pending': fee_pending})
        top_defaulters = sorted(top_defaulters, key=lambda x: x['pending'], reverse=True)[:5]
        
        # Monthly trend (last 6 months)
        months_labels = []
        months_amounts = []
        for i in range(5, -1, -1):
            m = today.month - i
            y = today.year
            if m <= 0:
                m += 12
                y -= 1
            total = PaymentTransaction.objects.filter(payment_date__year=y, payment_date__month=m).aggregate(Sum('amount'))['amount__sum'] or 0
            months_labels.append(f"{m}/{y}")
            months_amounts.append(float(total))

    context = {
        'tenant': tenant,
        'today_collection': today_collection,
        'month_collection': month_collection,
        'total_revenue': total_revenue,
        'total_pending': total_pending,
        'defaulters_count': defaulters_count,
        'total_students': total_students,
        'low_stock_count': low_stock_count,
        'collection_rate': round(collection_rate, 1),
        'recent_payments': recent_payments,
        'top_defaulters': top_defaulters,
        'months_labels': months_labels,
        'months_amounts': months_amounts,
        'logo_url': tenant.school_logo.url if tenant.school_logo else None,
        'today': today,
        'start_date': first_day_month,
    }
    return render(request, 'tenant/dashboard.html', context)"""

    # Replace the old function with the new one
    new_content = content.replace(old_dashboard, new_dashboard)

    # Write back
    with open(views_path, "w") as f:
        f.write(new_content)

    print("✅ Dashboard function fixed and cleaned up.")
    print("   - Total Pending now uses get_overall_pending (matching defaulters page).")
    print("   - Collection rate calculated correctly.")
    print("   - All duplicate code removed.")
    print("   Restart server: python manage.py runserver")

if __name__ == "__main__":
    patch_dashboard()
