from django.contrib import admin

from .models import Exam, ExamPaper, GradeBand, Mark


class ExamPaperInline(admin.TabularInline):
    model = ExamPaper
    extra = 0
    autocomplete_fields = []


@admin.register(Exam)
class ExamAdmin(admin.ModelAdmin):
    list_display = ('name', 'academic_year', 'start_date', 'is_published', 'school')
    list_filter = ('academic_year', 'is_published')
    search_fields = ('name',)
    inlines = [ExamPaperInline]


@admin.register(Mark)
class MarkAdmin(admin.ModelAdmin):
    list_display = ('student', 'paper', 'marks_obtained', 'is_absent', 'updated_at')
    list_filter = ('paper__exam', 'is_absent')
    search_fields = ('student__first_name', 'student__admission_number')
    raw_id_fields = ('student', 'paper', 'entered_by')


@admin.register(GradeBand)
class GradeBandAdmin(admin.ModelAdmin):
    list_display = ('label', 'min_percentage', 'description', 'school')
    list_filter = ('school',)
