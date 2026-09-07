from django.contrib import admin
from .models import Homework


@admin.register(Homework)
class HomeworkAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'subject',
        'classroom',
        'assigned_by',
        'assigned_date',
        'due_date',
        'school',
        'is_active',
    )
    list_filter = ('school', 'classroom', 'subject', 'due_date', 'is_active')
    search_fields = ('title', 'subject', 'description', 'assigned_by__username', 'school__name')
