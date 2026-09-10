from rest_framework import serializers
from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    target_id = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = [
            'id',
            'notification_type',
            'title',
            'message',
            'is_read',
            'homework',
            'announcement',
            'target_id',
            'created_at',
        ]
        read_only_fields = [
            'id',
            'notification_type',
            'title',
            'message',
            'homework',
            'announcement',
            'target_id',
            'created_at',
        ]

    def get_target_id(self, obj):
        if obj.homework_id:
            return obj.homework_id
        if obj.announcement_id:
            return obj.announcement_id
        return None
