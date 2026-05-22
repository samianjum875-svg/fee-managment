import re
with open('axis_saas/views.py', 'r') as f:
    content = f.read()
# Split the bad line
content = content.replace(
    "print(f'DEBUG fee_collection: total_payments={PaymentTransaction.objects.count()}, recent_count={recent_payments.count()}')        top_defaulters = []",
    "print(f'DEBUG fee_collection: total_payments={PaymentTransaction.objects.count()}, recent_count={recent_payments.count()}')\n        top_defaulters = []"
)
with open('axis_saas/views.py', 'w') as f:
    f.write(content)
print("Fixed")
