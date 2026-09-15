from rest_framework import serializers

from apps.schools.services import get_school_for

from .models import Subject, TimetableSlot


class SubjectSerializer(serializers.ModelSerializer):
    class Meta:
        model = Subject
        fields = ['id', 'name', 'code', 'is_active', 'created_at']
        read_only_fields = ['id', 'created_at']

    def validate_name(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError("Subject name is required.")

        request = self.context.get('request')
        if request is None:
            return name

        # Case-insensitive uniqueness: "Maths" and "maths" are one subject.
        clash = Subject.objects.filter(
            school=get_school_for(request.user), name__iexact=name
        )
        if self.instance:
            clash = clash.exclude(id=self.instance.id)
        if clash.exists():
            raise serializers.ValidationError(f"'{name}' already exists.")
        return name


class TimetableSlotSerializer(serializers.ModelSerializer):
    subject_name = serializers.CharField(source='subject.name', read_only=True)
    subject_code = serializers.CharField(source='subject.code', read_only=True)
    classroom_name = serializers.CharField(source='classroom.__str__', read_only=True)
    teacher_name = serializers.SerializerMethodField()
    weekday_name = serializers.CharField(source='get_weekday_display', read_only=True)
    time_display = serializers.CharField(read_only=True)

    class Meta:
        model = TimetableSlot
        fields = [
            'id',
            'classroom',
            'classroom_name',
            'weekday',
            'weekday_name',
            'period',
            'subject',
            'subject_name',
            'subject_code',
            'teacher',
            'teacher_name',
            'start_time',
            'end_time',
            'time_display',
            'room',
        ]
        read_only_fields = ['id']

    def get_teacher_name(self, obj):
        if not obj.teacher:
            return None
        name = f"{obj.teacher.first_name} {obj.teacher.last_name}".strip()
        return name or obj.teacher.username

    def validate(self, attrs):
        request = self.context.get('request')
        school = get_school_for(request.user) if request else None

        classroom = attrs.get('classroom') or getattr(self.instance, 'classroom', None)
        subject = attrs.get('subject') or getattr(self.instance, 'subject', None)
        teacher = attrs.get('teacher', getattr(self.instance, 'teacher', None))

        if school and classroom and classroom.school_id != school.id:
            raise serializers.ValidationError(
                {'classroom': "That class belongs to another school."}
            )
        if school and subject and subject.school_id != school.id:
            raise serializers.ValidationError(
                {'subject': "That subject belongs to another school."}
            )
        if teacher and teacher.role != 'TEACHER':
            raise serializers.ValidationError(
                {'teacher': f"'{teacher.username}' is not a teacher."}
            )

        start = attrs.get('start_time', getattr(self.instance, 'start_time', None))
        end = attrs.get('end_time', getattr(self.instance, 'end_time', None))
        if start and end and end <= start:
            raise serializers.ValidationError(
                {'end_time': 'End time must be after start time.'}
            )

        # A teacher cannot be in two classrooms in the same period.
        weekday = attrs.get('weekday', getattr(self.instance, 'weekday', None))
        period = attrs.get('period', getattr(self.instance, 'period', None))
        if teacher and weekday is not None and period is not None:
            clash = TimetableSlot.objects.filter(
                teacher=teacher, weekday=weekday, period=period
            )
            if self.instance:
                clash = clash.exclude(id=self.instance.id)
            clash = clash.exclude(classroom=classroom) if classroom else clash
            existing = clash.select_related('classroom').first()
            if existing:
                raise serializers.ValidationError({
                    'teacher': (
                        f"{self.get_teacher_name(existing)} already teaches "
                        f"{existing.classroom} in period {period} on "
                        f"{existing.get_weekday_display()}."
                    )
                })

        return attrs
