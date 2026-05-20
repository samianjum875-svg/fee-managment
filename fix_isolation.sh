#!/bin/bash
FILE="axis_saas/public_urls.py"

# Add import for schema_context if missing
if ! grep -q "from django_tenants.utils import schema_context" "$FILE"; then
    sed -i '/from django.contrib import messages/a from django_tenants.utils import schema_context' "$FILE"
fi

# Fix school_students_list: wrap Student query in schema_context
sed -i '/def school_students_list/,/return render/ {
    /students = Student.objects.all/ {
        i\    with schema_context(tenant.schema_name):
        s/students = Student.objects.all/        students = Student.objects.all/
    }
}' "$FILE"

# Fix school_add_student: wrap POST and GET logic in schema_context
sed -i '/def school_add_student/,/return render/ {
    /if request.method == .POST.:/ {
        i\    with schema_context(tenant.schema_name):
    }
    /total_students = Student.objects.count/ {
        i\        with schema_context(tenant.schema_name):
    }
}' "$FILE"

echo "✅ Tenant isolation patch applied to $FILE"
echo "👉 Restart Django server now:"
echo "   python manage.py runserver"
