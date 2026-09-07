from rest_framework import serializers
from .models import Class, Student


class ClassSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    school_code = serializers.CharField(source='school.code', read_only=True)
    display_name = serializers.SerializerMethodField()

    class Meta:
        model = Class
        fields = [
            'id',
            'school',
            'school_name',
            'school_code',
            'name',
            'section',
            'academic_year',
            'display_name',
            'is_active',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'school', 'created_at', 'updated_at']

    def get_display_name(self, obj):
        return str(obj)


class StudentSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    full_name = serializers.CharField(read_only=True)
    class_name = serializers.CharField(source='class_enrolled.__str__', read_only=True)

    class Meta:
        model = Student
        fields = [
            'id',
            'school',
            'school_name',
            'admission_number',
            'first_name',
            'last_name',
            'full_name',
            'date_of_birth',
            'class_enrolled',
            'class_name',
            'is_active',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'school', 'created_at', 'updated_at']

    def validate_class_enrolled(self, value):
        """
        Validate that the assigned class belongs to the user's school.
        """
        if value:
            request = self.context.get('request')
            if request and hasattr(request, 'user'):
                user = request.user
                if not user.is_superuser and user.school != value.school:
                    raise serializers.ValidationError(
                        "Cannot assign a student to a class from a different school."
                    )
        return value
