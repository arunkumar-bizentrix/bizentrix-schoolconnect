from rest_framework import serializers

from apps.schools.services import get_school_for
from django.core.exceptions import ValidationError as DjangoValidationError
from apps.schools.downloads import private_file_url
from .models import Announcement
from .validators import validate_announcement_attachment


class AnnouncementSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    target_class_name = serializers.CharField(source='target_class.__str__', read_only=True)
    academic_year = serializers.CharField(source='target_class.academic_year', read_only=True)
    created_by_name = serializers.SerializerMethodField()
    attachment_url = serializers.SerializerMethodField()
    is_active = serializers.BooleanField(default=True, required=False)

    attachment_name = serializers.SerializerMethodField()

    class Meta:
        extra_kwargs = {'attachment': {'write_only': True}}
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
            'attachment_name',
            'priority',
            'audience_type',
            'target_class',
            'target_class_name',
            'academic_year',
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
        # The permission-checked download route, never the /media/ path.
        if not obj.attachment:
            return None
        return private_file_url(self.context.get('request'), f'/api/v1/announcements/{obj.id}/attachment/')

    def get_attachment_name(self, obj):
        import os
        return os.path.basename(obj.attachment.name) if obj.attachment else None

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
            if not user.is_superuser and target_class.school != get_school_for(user):
                raise serializers.ValidationError({
                    'target_class': "Target class must belong to the same school."
                })
        elif audience_type == Announcement.AudienceType.SCHOOL:
            if target_class is not None:
                raise serializers.ValidationError({
                    'target_class': "Target class must be null when audience type is SCHOOL."
                })

        return attrs
