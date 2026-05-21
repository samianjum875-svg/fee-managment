from django.urls import path, include
from django.shortcuts import redirect
from . import views

def tenant_root(request):
    return redirect('dashboard', schema_name=request.tenant.schema_name)

urlpatterns = [
    path('', tenant_root, name='tenant_root'),
    path('dashboard/', views.dashboard, name='dashboard'),
    path('students/', views.student_list, name='student_list'),
    path('students/add/', views.add_student, name='add_student'),
    path('students/edit/<int:student_id>/', views.edit_student, name='edit_student'),
    path('students/<int:student_id>/', views.student_profile, name='student_profile'),
    path('fee/collection/', views.fee_collection, name='fee_collection'),
    path('fee/collection/<int:student_id>/', views.fee_collection, name='fee_collection'),
    path('fee/receipt/<int:receipt_id>/', views.fee_receipt, name='fee_receipt'),
    path('defaulters/', views.defaulters, name='defaulters'),
    path('reports/', views.reports, name='reports'),
    path('settings/', views.settings, name='settings'),
    path('fee/structure/', views.fee_structure, name='fee_structure'),
    path('fee/settings/', views.fee_settings, name='fee_settings'),
    path('fee/family-payment/', views.family_payment, name='family_payment'),
    path('api/student-search/', views.student_search_api, name='student_search_api'),
]
