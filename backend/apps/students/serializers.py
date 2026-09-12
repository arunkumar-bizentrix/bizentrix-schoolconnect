from rest_framework import serializers

from apps.schools.services import get_school_id_for
from .models import (
    Class,
    Student,
    StudentClassEnrollment,
    normalize_academic_year,
    validate_academic_year_format,
)


class ClassSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    school_code = serializers.CharField(source='school.code', read_only=True)
    display_name = serializers.SerializerMethodField()
    teacher_names = serializers.SerializerMethodField()
    student_count = serializers.SerializerMethodField()
    is_active = serializers.BooleanField(default=True, required=False)

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
            'teachers',
            'teacher_names',
            'display_name',
            'student_count',
            'is_active',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'school', 'created_at', 'updated_at']

    def get_display_name(self, obj):
        return str(obj)

    def get_student_count(self, obj):
        """
        Number of active students in the class. Uses the queryset annotation
        when present (list/detail reads) and falls back to a direct count for
        freshly created instances, which are not annotated.
        """
        annotated = getattr(obj, 'student_count', None)
        if annotated is not None:
            return annotated
        return obj.students.filter(is_active=True).count()

    def get_teacher_names(self, obj):
        return [
            f"{t.first_name} {t.last_name}".strip() or t.username
            for t in obj.teachers.all()
        ]

    def validate_academic_year(self, value):
        if value:
            norm = normalize_academic_year(value)
            validate_academic_year_format(norm)
            return norm
        return value

    def validate_teachers(self, value):
        request = self.context.get('request')
        if request and hasattr(request, 'user'):
            user = request.user
            if not user.is_superuser:
                school_id = get_school_id_for(user)
                for teacher in value:
                    if teacher.school_id != school_id:
                        raise serializers.ValidationError(
                            "Cannot assign a teacher from another school."
                        )
                    if teacher.role != 'TEACHER':
                        raise serializers.ValidationError(
                            f"User '{teacher.username}' does not have the TEACHER role."
                        )
        return value


class StudentClassEnrollmentSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    student_name = serializers.CharField(source='student.full_name', read_only=True)
    classroom_name = serializers.CharField(source='classroom.__str__', read_only=True)

    class Meta:
        model = StudentClassEnrollment
        fields = [
            'id',
            'school',
            'school_name',
            'student',
            'student_name',
            'classroom',
            'classroom_name',
            'academic_year',
            'start_date',
            'end_date',
            'is_current',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'school', 'student', 'created_at', 'updated_at']

    def validate_academic_year(self, value):
        if value:
            norm = normalize_academic_year(value)
            validate_academic_year_format(norm)
            return norm
        return value

    def validate(self, attrs):
        request = self.context.get('request')
        student = attrs.get('student') or self.context.get('student')
        classroom = attrs.get('classroom')

        if not student:
            raise serializers.ValidationError({'student': "Student is required."})

        if request and hasattr(request, 'user') and not request.user.is_superuser:
            user = request.user
            school_id = get_school_id_for(user)
            if student and student.school_id != school_id:
                raise serializers.ValidationError({
                    'student': "Student must belong to your school."
                })
            if classroom and classroom.school_id != school_id:
                raise serializers.ValidationError({
                    'classroom': "Classroom must belong to your school."
                })

        if student and classroom and student.school_id != classroom.school_id:
            raise serializers.ValidationError(
                "Student and Classroom must belong to the same school."
            )

        return attrs


class StudentSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    full_name = serializers.CharField(read_only=True)
    class_name = serializers.CharField(source='class_enrolled.__str__', read_only=True)
    academic_year = serializers.SerializerMethodField()
    is_active = serializers.BooleanField(default=True, required=False)

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
            'academic_year',
            'parents',
            'is_active',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'school', 'created_at', 'updated_at']

    def get_academic_year(self, obj):
        if obj.class_enrolled:
            return obj.class_enrolled.academic_year
        return None

    def validate_class_enrolled(self, value):
        if value:
            request = self.context.get('request')
            if request and hasattr(request, 'user'):
                user = request.user
                if not user.is_superuser and get_school_id_for(user) != value.school_id:
                    raise serializers.ValidationError(
                        "Cannot assign a student to a class from a different school."
                    )
        return value

    def validate_parents(self, value):
        if value:
            request = self.context.get('request')
            if request and hasattr(request, 'user'):
                user = request.user
                if not user.is_superuser:
                    school_id = get_school_id_for(user)
                    for parent in value:
                        if parent.school_id != school_id:
                            raise serializers.ValidationError(
                                "Cannot associate a parent from another school."
                            )
                        if parent.role != 'PARENT':
                            raise serializers.ValidationError(
                                f"User '{parent.username}' does not have the PARENT role."
                            )
        return value
