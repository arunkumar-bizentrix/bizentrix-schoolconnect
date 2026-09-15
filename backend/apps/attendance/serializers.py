from rest_framework import serializers

from .models import Attendance


class AttendanceSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.full_name', read_only=True)
    admission_number = serializers.CharField(
        source='student.admission_number', read_only=True)
    classroom_name = serializers.CharField(source='classroom.__str__', read_only=True)
    marked_by_name = serializers.SerializerMethodField()

    class Meta:
        model = Attendance
        fields = [
            'id',
            'student',
            'student_name',
            'admission_number',
            'classroom',
            'classroom_name',
            'date',
            'status',
            'note',
            'marked_by',
            'marked_by_name',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'marked_by', 'created_at', 'updated_at']

    def get_marked_by_name(self, obj):
        if not obj.marked_by:
            return 'School'
        name = f"{obj.marked_by.first_name} {obj.marked_by.last_name}".strip()
        return name or obj.marked_by.username


class AttendanceEntrySerializer(serializers.Serializer):
    """One student's mark inside a bulk class submission."""
    student = serializers.IntegerField()
    status = serializers.ChoiceField(choices=Attendance.Status.choices)
    note = serializers.CharField(required=False, allow_blank=True, max_length=255)


class MarkAttendanceSerializer(serializers.Serializer):
    """
    A whole class marked in one request.

    Marking a class twice for the same day corrects it rather than creating
    duplicates - teachers do fix a mark after a late arrival.
    """
    classroom = serializers.IntegerField()
    date = serializers.DateField()
    entries = AttendanceEntrySerializer(many=True)

    def validate_entries(self, value):
        if not value:
            raise serializers.ValidationError("Mark at least one student.")
        seen = set()
        for entry in value:
            if entry['student'] in seen:
                raise serializers.ValidationError(
                    f"Student {entry['student']} appears more than once."
                )
            seen.add(entry['student'])
        return value

    def validate_date(self, value):
        from django.utils import timezone
        if value > timezone.localdate():
            raise serializers.ValidationError(
                "Attendance cannot be marked for a future date."
            )
        return value
