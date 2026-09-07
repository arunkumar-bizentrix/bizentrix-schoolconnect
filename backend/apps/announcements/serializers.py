from rest_framework import serializers
from django.core.exceptions import ValidationError as DjangoValidationError
from .models import Announcement
from .validators import validate_announcement_attachment


class AnnouncementSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    target_class_name = serializers.CharField(source='target_class.__str__', read_only=True)
    created_by_name = serializers.SerializerMethodField()
    attachment_url = serializers.SerializerMethodField()

    class Meta:
        model = Announcement
        fields = [
            'id',
            'school',
            'school_name',
            'title',
            'content',
            'created_by',
            'created_by_name',
            'published_at',
            'attachment',
            'attachment_url',
            'priority',
            'audience_type',
            'target_class',
            'target_class_name',
            'is_active',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'school', 'created_by', 'created_at', 'updated_at']

    def get_created_by_name(self, obj):
        if not obj.created_by:
            return 'School Administration'
        full_name = f"{obj.created_by.first_name} {obj.created_by.last_name}".strip()
        return full_name or obj.created_by.username

    def get_attachment_url(self, obj):
        if not obj.attachment:
            return None
        request = self.context.get('request')
        if request:
            return request.build_absolute_uri(obj.attachment.url)
        return obj.attachment.url

    def validate_attachment(self, value):
        if value:
            try:
                validate_announcement_attachment(value)
            except DjangoValidationError as exc:
                raise serializers.ValidationError(list(exc.messages))
        return value

    def validate(self, attrs):
        user = self.context['request'].user
        audience_type = attrs.get(
            'audience_type',
            getattr(self.instance, 'audience_type', Announcement.AudienceType.SCHOOL)
        )
        target_class = attrs.get(
            'target_class',
            getattr(self.instance, 'target_class', None)
        )

        if audience_type == Announcement.AudienceType.CLASS:
            if not target_class:
                raise serializers.ValidationError({
                    'target_class': "Target class is required when audience type is CLASS."
                })
            # Multi-tenant cross-school validation
            if not user.is_superuser and target_class.school != user.school:
                raise serializers.ValidationError({
                    'target_class': "Target class must belong to the same school."
                })
        elif audience_type == Announcement.AudienceType.SCHOOL:
            if target_class is not None:
                raise serializers.ValidationError({
                    'target_class': "Target class must be null when audience type is SCHOOL."
                })

        return attrs
