from django.contrib import admin
from .models import School


@admin.register(School)
class SchoolAdmin(admin.ModelAdmin):
    list_display = ('name', 'code', 'contact_phone', 'is_active', 'created_at')
    search_fields = ('name', 'code', 'contact_email')
    list_filter = ('is_active',)
