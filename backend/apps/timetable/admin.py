from django.contrib import admin

from .models import Subject, TimetableSlot


@admin.register(Subject)
class SubjectAdmin(admin.ModelAdmin):
    list_display = ('name', 'code', 'school', 'is_active')
    list_filter = ('school', 'is_active')
    search_fields = ('name', 'code')


@admin.register(TimetableSlot)
class TimetableSlotAdmin(admin.ModelAdmin):
    list_display = ('classroom', 'weekday', 'period', 'subject', 'teacher', 'time_display')
    list_filter = ('weekday', 'classroom', 'subject')
    raw_id_fields = ('classroom', 'teacher')
