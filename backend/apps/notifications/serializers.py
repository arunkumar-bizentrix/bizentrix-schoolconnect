from rest_framework import serializers
from .models import DeviceToken, Notification


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
            'attendance',
            'exam',
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
            'attendance',
            'exam',
            'target_id',
            'created_at',
        ]

    def get_target_id(self, obj):
        if obj.homework_id:
            return obj.homework_id
        if obj.announcement_id:
            return obj.announcement_id
        if obj.attendance_id:
            return obj.attendance_id
        if obj.exam_id:
            return obj.exam_id
        return None


class DeviceTokenSerializer(serializers.ModelSerializer):
    """Registers the phone the signed-in user is holding."""

    # The view upserts on this token deliberately - re-registering the same
    # phone must update the row, not fail as a duplicate - so the model's
    # unique validator is dropped here.
    token = serializers.CharField(max_length=512, validators=[])

    class Meta:
        model = DeviceToken
        fields = ['id', 'token', 'platform', 'device_name', 'is_active', 'last_seen_at']
        read_only_fields = ['id', 'is_active', 'last_seen_at']

    def validate_token(self, value):
        token = (value or '').strip()
        if len(token) < 20:
            raise serializers.ValidationError("That does not look like a device token.")
        return token
