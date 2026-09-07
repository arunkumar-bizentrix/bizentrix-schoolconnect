from django.contrib import admin
from .models import Class, Student


@admin.register(Class)
class ClassAdmin(admin.ModelAdmin):
    list_display = ('name', 'section', 'academic_year', 'school', 'is_active', 'created_at')
    list_filter = ('school', 'academic_year', 'is_active')
    search_fields = ('name', 'section', 'academic_year', 'school__name')


@admin.register(Student)
class StudentAdmin(admin.ModelAdmin):
    list_display = (
        'admission_number',
        'first_name',
        'last_name',
        'class_enrolled',
        'school',
        'is_active',
        'created_at',
    )
    list_filter = ('school', 'class_enrolled', 'is_active')
    search_fields = ('admission_number', 'first_name', 'last_name', 'school__name')
