from django.contrib import admin
from .models import Announcement


@admin.register(Announcement)
class AnnouncementAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'priority',
        'audience_type',
        'target_class',
        'school',
        'created_by',
        'published_at',
        'is_active',
    )
    list_filter = (
        'school',
        'priority',
        'audience_type',
        'is_active',
        'published_at',
    )
    search_fields = (
        'title',
        'content',
        'school__name',
        'created_by__username',
        'target_class__name',
    )
