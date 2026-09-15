from django.contrib import admin

from .models import DeviceToken, Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = (
        'title',
        'notification_type',
        'recipient',
        'is_read',
        'created_at',
    )
    list_filter = ('notification_type', 'is_read', 'created_at')
    search_fields = ('title', 'message', 'recipient__username')
    raw_id_fields = ('recipient', 'homework', 'announcement')


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ('user', 'platform', 'device_name', 'is_active', 'last_seen_at')
    list_filter = ('platform', 'is_active')
    search_fields = ('user__username', 'device_name')
    raw_id_fields = ('user',)
