from rest_framework import serializers

from apps.students.models import Class, normalize_academic_year, validate_academic_year_format
from apps.timetable.models import Subject

from .models import Exam, ExamPaper


class ExamPaperSerializer(serializers.ModelSerializer):
    classroom_name = serializers.SerializerMethodField()
    subject_name = serializers.CharField(source='subject.name', read_only=True)
    entered_count = serializers.IntegerField(read_only=True, default=None)
    can_enter_marks = serializers.SerializerMethodField()

    class Meta:
        model = ExamPaper
        fields = [
            'id', 'exam', 'classroom', 'classroom_name', 'subject', 'subject_name',
            'max_marks', 'pass_marks', 'exam_date', 'entered_count', 'can_enter_marks',
        ]
        read_only_fields = ['id', 'exam', 'classroom', 'subject']

    def get_classroom_name(self, obj):
        return f'{obj.classroom.name} - {obj.classroom.section}'

    def get_can_enter_marks(self, obj):
        checker = self.context.get('can_enter_marks')
        return bool(checker(obj)) if checker else False

    def validate(self, attrs):
        max_marks = attrs.get('max_marks', getattr(self.instance, 'max_marks', 100))
        pass_marks = attrs.get('pass_marks', getattr(self.instance, 'pass_marks', 33))
        if max_marks == 0:
            raise serializers.ValidationError({'max_marks': 'Maximum marks must be more than zero.'})
        if pass_marks > max_marks:
            raise serializers.ValidationError({'pass_marks': 'Pass marks cannot exceed maximum marks.'})

        if self.instance is not None and 'max_marks' in attrs:
            highest = self.instance.marks.exclude(marks_obtained__isnull=True).order_by(
                '-marks_obtained'
            ).values_list('marks_obtained', flat=True).first()
            if highest is not None and highest > max_marks:
                raise serializers.ValidationError({
                    'max_marks': f'A student already scored {highest:g}; the maximum cannot be lower.'
                })
        return attrs


class ExamSerializer(serializers.ModelSerializer):
    """
    Creating an exam also sets out its papers: pick the classes and the
    subjects they write, with common maximum and pass marks. Individual papers
    can be adjusted afterwards (a practical out of 50, a date per subject).
    """

    classroom_ids = serializers.ListField(
        child=serializers.IntegerField(), write_only=True, required=False
    )
    subject_ids = serializers.ListField(
        child=serializers.IntegerField(), write_only=True, required=False
    )
    max_marks = serializers.IntegerField(write_only=True, required=False, min_value=1, default=100)
    pass_marks = serializers.IntegerField(write_only=True, required=False, min_value=0, default=33)

    classrooms = serializers.SerializerMethodField()
    subjects = serializers.SerializerMethodField()
    paper_count = serializers.SerializerMethodField()
    created_by_name = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id', 'name', 'academic_year', 'start_date', 'end_date',
            'is_published', 'published_at', 'created_by_name', 'created_at',
            'classrooms', 'subjects', 'paper_count',
            'classroom_ids', 'subject_ids', 'max_marks', 'pass_marks',
        ]
        read_only_fields = ['id', 'is_published', 'published_at', 'created_at']

    # --- read ---------------------------------------------------------------

    def _papers(self, obj):
        # Prefetched by the viewset; never a query per exam.
        return list(obj.papers.all())

    def get_classrooms(self, obj):
        seen = {}
        for paper in self._papers(obj):
            seen[paper.classroom_id] = f'{paper.classroom.name} - {paper.classroom.section}'
        return [{'id': key, 'name': value} for key, value in sorted(seen.items(), key=lambda i: i[1])]

    def get_subjects(self, obj):
        return sorted({paper.subject.name for paper in self._papers(obj)})

    def get_paper_count(self, obj):
        return len(self._papers(obj))

    def get_created_by_name(self, obj):
        user = obj.created_by
        if user is None:
            return None
        return f'{user.first_name} {user.last_name}'.strip() or user.username

    # --- write --------------------------------------------------------------

    def validate_academic_year(self, value):
        normalized = normalize_academic_year(value)
        validate_academic_year_format(normalized)
        return normalized

    def validate(self, attrs):
        start = attrs.get('start_date', getattr(self.instance, 'start_date', None))
        end = attrs.get('end_date', getattr(self.instance, 'end_date', None))
        if start and end and end < start:
            raise serializers.ValidationError({'end_date': 'End date cannot be before the start date.'})

        if attrs.get('pass_marks', 33) > attrs.get('max_marks', 100):
            raise serializers.ValidationError({'pass_marks': 'Pass marks cannot exceed maximum marks.'})

        school = self.context['school']
        if self.instance is None:
            classroom_ids = attrs.get('classroom_ids') or []
            subject_ids = attrs.get('subject_ids') or []
            if not classroom_ids:
                raise serializers.ValidationError({'classroom_ids': 'Choose at least one class.'})
            if not subject_ids:
                raise serializers.ValidationError({'subject_ids': 'Choose at least one subject.'})

            classrooms = list(Class.objects.filter(id__in=classroom_ids, school=school))
            subjects = list(Subject.objects.filter(id__in=subject_ids, school=school))
            if len(classrooms) != len(set(classroom_ids)):
                raise serializers.ValidationError({'classroom_ids': 'One or more classes were not found.'})
            if len(subjects) != len(set(subject_ids)):
                raise serializers.ValidationError({'subject_ids': 'One or more subjects were not found.'})
            attrs['_classrooms'] = classrooms
            attrs['_subjects'] = subjects
        return attrs

    def create(self, validated_data):
        classrooms = validated_data.pop('_classrooms')
        subjects = validated_data.pop('_subjects')
        max_marks = validated_data.pop('max_marks', 100)
        pass_marks = validated_data.pop('pass_marks', 33)
        validated_data.pop('classroom_ids', None)
        validated_data.pop('subject_ids', None)

        exam = Exam.objects.create(**validated_data)
        ExamPaper.objects.bulk_create([
            ExamPaper(
                exam=exam, classroom=classroom, subject=subject,
                max_marks=max_marks, pass_marks=pass_marks,
            )
            for classroom in classrooms
            for subject in subjects
        ])
        return exam

    def update(self, instance, validated_data):
        for field in ('classroom_ids', 'subject_ids', 'max_marks', 'pass_marks'):
            validated_data.pop(field, None)
        return super().update(instance, validated_data)


class MarkEntrySerializer(serializers.Serializer):
    student = serializers.IntegerField()
    marks_obtained = serializers.DecimalField(
        max_digits=5, decimal_places=1, required=False, allow_null=True, min_value=0
    )
    is_absent = serializers.BooleanField(required=False, default=False)
    remarks = serializers.CharField(required=False, allow_blank=True, max_length=160, default='')


class MarkSheetSubmitSerializer(serializers.Serializer):
    entries = MarkEntrySerializer(many=True)


class GradeBandSerializer(serializers.Serializer):
    label = serializers.CharField(max_length=8)
    min_percentage = serializers.DecimalField(max_digits=5, decimal_places=2)
    description = serializers.CharField(max_length=60, required=False, allow_blank=True, default='')
