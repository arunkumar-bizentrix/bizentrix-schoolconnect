from django.utils import timezone
from rest_framework import serializers
from .models import Homework


class HomeworkSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    classroom_name = serializers.CharField(source='classroom.__str__', read_only=True)
    assigned_by_name = serializers.SerializerMethodField()
    attachment_url = serializers.SerializerMethodField()

    class Meta:
        model = Homework
        fields = [
            'id',
            'school',
            'school_name',
            'classroom',
            'classroom_name',
            'subject',
            'title',
            'description',
            'assigned_by',
            'assigned_by_name',
            'assigned_date',
            'due_date',
            'attachment',
            'attachment_url',
            'is_active',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'school', 'assigned_by', 'created_at', 'updated_at']

    def get_assigned_by_name(self, obj):
        if not obj.assigned_by:
            return 'School Administration'
        full_name = f"{obj.assigned_by.first_name} {obj.assigned_by.last_name}".strip()
        return full_name or obj.assigned_by.username

    def get_attachment_url(self, obj):
        if not obj.attachment:
            return None
        request = self.context.get('request')
        if request:
            return request.build_absolute_uri(obj.attachment.url)
        return obj.attachment.url

    def validate_classroom(self, value):
        """
        Validate that the selected class belongs to the user's school.
        """
        request = self.context.get('request')
        if request and hasattr(request, 'user'):
            user = request.user
            if not user.is_superuser and value.school != user.school:
                raise serializers.ValidationError(
                    "Cannot assign homework to a class from another school."
                )
        return value

    def validate(self, attrs):
        """
        Validate that due_date is not earlier than assigned_date.
        """
        assigned_date = attrs.get('assigned_date', timezone.now().date())
        due_date = attrs.get('due_date')

        if due_date and assigned_date and due_date < assigned_date:
            raise serializers.ValidationError({
                'due_date': 'Due date cannot be earlier than assigned date.'
            })

        return attrs
