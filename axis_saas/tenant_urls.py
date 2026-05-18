from django.urls import path
from django.shortcuts import render, redirect
from django.contrib.auth.decorators import login_required
from django.contrib.auth import logout
from axis_saas.models import Student

@login_required(login_url='/admin/login/')
def school_dashboard(request):
    # Isolated context execution ensures only this school's students are populated!
    students = Student.objects.all().order_by('-enrolled_on')
    return render(request, 'tenant/dashboard.html', {'students': students})

@login_required(login_url='/admin/login/')
def add_student(request):
    if request.method == 'POST':
        name = request.POST.get('name')
        roll_number = request.POST.get('roll_number')
        grade = request.POST.get('grade')
        
        if name and roll_number and grade:
            Student.objects.create(name=name, roll_number=roll_number, grade=grade)
            return redirect('school_home')
            
    return render(request, 'tenant/student_form.html')

def school_logout(request):
    logout(request)
    return redirect('/admin/login/')

urlpatterns = [
    path('', school_dashboard, name='school_home'),
    path('add-student/', add_student, name='add_student'),
    path('logout/', school_logout, name='school_logout'),
]
