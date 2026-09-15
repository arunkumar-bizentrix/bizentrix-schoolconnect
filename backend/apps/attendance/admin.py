from django.contrib import admin

from .models import Attendance


@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    list_display = ('student', 'date', 'status', 'classroom', 'marked_by')
    list_filter = ('status', 'date', 'classroom')
    search_fields = ('student__first_name', 'student__last_name', 'student__admission_number')
    raw_id_fields = ('student', 'classroom', 'marked_by')
    date_hierarchy = 'date'
