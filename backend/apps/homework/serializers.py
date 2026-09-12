from django.utils import timezone
from rest_framework import serializers

from apps.schools.services import get_school_for
from .models import Homework


class HomeworkSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    classroom_name = serializers.CharField(source='classroom.__str__', read_only=True)
    academic_year = serializers.CharField(source='classroom.academic_year', read_only=True)
    student_name = serializers.SerializerMethodField()
    assigned_by_name = serializers.SerializerMethodField()
    attachment_url = serializers.SerializerMethodField()
    is_active = serializers.BooleanField(default=True, required=False)

    class Meta:
        model = Homework
        fields = [
            'id',
            'school',
            'school_name',
            'classroom',
            'classroom_name',
            'academic_year',
            'student',
            'student_name',
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

    def get_student_name(self, obj):
        if not obj.student:
            return None
        full = f"{obj.student.first_name} {obj.student.last_name}".strip()
        return full or obj.student.admission_number

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
            if not user.is_superuser and value.school != get_school_for(user):
                raise serializers.ValidationError(
                    "Cannot assign homework to a class from another school."
                )
        return value

    def validate(self, attrs):
        """
        Validate:
        1. due_date cannot be in the past (must be today or future).
        2. due_date cannot be earlier than assigned_date.
        3. If student is specified, student must belong to the selected class.
        """
        today = timezone.localdate()
        assigned_date = attrs.get('assigned_date', today)
        due_date = attrs.get('due_date')

        if due_date and due_date < today:
            raise serializers.ValidationError({
                'due_date': 'Due date cannot be in the past. Please select today or a future date.'
            })

        if due_date and assigned_date and due_date < assigned_date:
            raise serializers.ValidationError({
                'due_date': 'Due date cannot be earlier than assigned date.'
            })

        classroom = attrs.get('classroom') or (self.instance.classroom if self.instance else None)
        student = attrs.get('student') or (self.instance.student if self.instance else None)

        if student and classroom:
            if student.class_enrolled_id and student.class_enrolled_id != classroom.id:
                raise serializers.ValidationError({
                    'student': f"Student '{student.full_name}' is not enrolled in '{classroom}'."
                })

        return attrs
