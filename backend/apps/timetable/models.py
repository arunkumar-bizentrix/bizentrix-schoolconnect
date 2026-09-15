from django.core.exceptions import ValidationError
from django.db import models


class Subject(models.Model):
    """
    A subject the school teaches.

    Homework used to carry the subject as free text, which meant "Maths",
    "Mathematics" and "maths" were three different subjects as far as any
    report was concerned. The timetable and, later, marks both need one row per
    real subject, so this is that row.
    """

    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='subjects',
    )
    name = models.CharField(max_length=80, help_text="e.g. Mathematics")
    code = models.CharField(
        max_length=16,
        blank=True,
        help_text="Optional short code used on timetables, e.g. MATH",
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['name']
        constraints = [
            models.UniqueConstraint(
                fields=['school', 'name'],
                name='unique_subject_name_per_school',
            ),
        ]
        indexes = [models.Index(fields=['school', 'is_active'])]

    def __str__(self):
        return self.name


class TimetableSlot(models.Model):
    """
    One period of one class on one weekday.

    Stored per (class, weekday, period) so a class's week is a simple query and
    a teacher's day is the same table filtered the other way.
    """

    class Weekday(models.IntegerChoices):
        MONDAY = 0, 'Monday'
        TUESDAY = 1, 'Tuesday'
        WEDNESDAY = 2, 'Wednesday'
        THURSDAY = 3, 'Thursday'
        FRIDAY = 4, 'Friday'
        SATURDAY = 5, 'Saturday'
        SUNDAY = 6, 'Sunday'

    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='timetable_slots',
    )
    classroom = models.ForeignKey(
        'students.Class',
        on_delete=models.CASCADE,
        related_name='timetable_slots',
    )
    weekday = models.IntegerField(choices=Weekday.choices)
    period = models.PositiveSmallIntegerField(help_text="Period number, starting at 1")
    subject = models.ForeignKey(
        Subject,
        on_delete=models.PROTECT,
        related_name='timetable_slots',
    )
    teacher = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='timetable_slots',
        limit_choices_to={'role': 'TEACHER'},
    )
    start_time = models.TimeField(null=True, blank=True)
    end_time = models.TimeField(null=True, blank=True)
    room = models.CharField(max_length=40, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['weekday', 'period']
        verbose_name = 'Timetable slot'
        verbose_name_plural = 'Timetable slots'
        constraints = [
            # A class cannot be in two places in the same period.
            models.UniqueConstraint(
                fields=['classroom', 'weekday', 'period'],
                name='unique_period_per_class',
            ),
        ]
        indexes = [
            models.Index(fields=['school', 'weekday']),
            models.Index(fields=['classroom', 'weekday']),
            models.Index(fields=['teacher', 'weekday']),
        ]

    def clean(self):
        super().clean()
        if self.start_time and self.end_time and self.end_time <= self.start_time:
            raise ValidationError({'end_time': 'End time must be after start time.'})

    @property
    def time_display(self):
        if not self.start_time:
            return f'Period {self.period}'
        start = self.start_time.strftime('%I:%M %p').lstrip('0')
        if not self.end_time:
            return start
        end = self.end_time.strftime('%I:%M %p').lstrip('0')
        return f'{start} - {end}'

    def __str__(self):
        return f'{self.classroom} · {self.get_weekday_display()} P{self.period} · {self.subject}'
