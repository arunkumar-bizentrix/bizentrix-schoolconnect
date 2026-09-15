from django.db import models


class Attendance(models.Model):
    """
    One student's attendance on one day.

    Recorded per (student, date): a class is marked as a whole, but the row is
    per student so a transfer mid-year keeps its history, and a parent's
    percentage is a straight count over these rows.
    """

    class Status(models.TextChoices):
        PRESENT = 'PRESENT', 'Present'
        ABSENT = 'ABSENT', 'Absent'
        LATE = 'LATE', 'Late'
        EXCUSED = 'EXCUSED', 'Excused'

    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='attendance_records',
    )
    student = models.ForeignKey(
        'students.Student',
        on_delete=models.CASCADE,
        related_name='attendance_records',
    )
    classroom = models.ForeignKey(
        'students.Class',
        on_delete=models.CASCADE,
        related_name='attendance_records',
        help_text="Class the student was in on this date",
    )
    date = models.DateField(db_index=True)
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.PRESENT,
    )
    note = models.CharField(
        max_length=255,
        blank=True,
        help_text="Optional reason, e.g. 'fever' or 'family function'",
    )
    marked_by = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='marked_attendance',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-date', 'student__admission_number']
        verbose_name = 'Attendance record'
        verbose_name_plural = 'Attendance records'
        # One row per student per day: re-marking a class corrects the day
        # rather than stacking duplicates.
        constraints = [
            models.UniqueConstraint(
                fields=['student', 'date'],
                name='unique_attendance_per_student_per_day',
            ),
        ]
        indexes = [
            models.Index(fields=['school', 'date']),
            models.Index(fields=['classroom', 'date']),
            models.Index(fields=['student', 'date']),
            models.Index(fields=['school', 'status']),
        ]

    def __str__(self):
        return f"{self.student} - {self.date} - {self.status}"

    @property
    def is_present(self):
        """Late still counts as attending; absent and excused do not."""
        return self.status in (self.Status.PRESENT, self.Status.LATE)
