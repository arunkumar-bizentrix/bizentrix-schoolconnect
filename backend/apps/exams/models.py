from django.core.exceptions import ValidationError
from django.db import models


class Exam(models.Model):
    """
    One examination the school conducts, e.g. "Quarterly Exam 2026-2027".

    An exam spans several classes; what each class actually writes is an
    ExamPaper. Results stay private to staff until the admin publishes them -
    otherwise a parent opening the app while marks are half entered sees a
    total and a rank that will change by tomorrow.
    """

    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='exams',
    )
    name = models.CharField(max_length=120, help_text="e.g. Quarterly Exam")
    academic_year = models.CharField(max_length=9, help_text="e.g. 2026-2027")
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    is_published = models.BooleanField(
        default=False,
        help_text="Parents see marks, totals and ranks only once this is on.",
    )
    published_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='exams_created',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-start_date', '-created_at']
        indexes = [
            models.Index(fields=['school', 'academic_year']),
            models.Index(fields=['school', 'is_published']),
        ]

    def clean(self):
        super().clean()
        if self.start_date and self.end_date and self.end_date < self.start_date:
            raise ValidationError({'end_date': 'End date cannot be before the start date.'})

    def __str__(self):
        return f'{self.name} ({self.academic_year})'


class ExamPaper(models.Model):
    """
    One subject written by one class in one exam - the unit marks are entered
    against, and whose maximum and pass marks decide the result.
    """

    exam = models.ForeignKey(Exam, on_delete=models.CASCADE, related_name='papers')
    classroom = models.ForeignKey(
        'students.Class',
        on_delete=models.CASCADE,
        related_name='exam_papers',
    )
    subject = models.ForeignKey(
        'timetable.Subject',
        on_delete=models.PROTECT,
        related_name='exam_papers',
    )
    max_marks = models.PositiveSmallIntegerField(default=100)
    # 33% of the default 100: grade D is a pass (see grading.py).
    pass_marks = models.PositiveSmallIntegerField(default=33)
    exam_date = models.DateField(null=True, blank=True)

    class Meta:
        ordering = ['exam_date', 'subject__name']
        constraints = [
            models.UniqueConstraint(
                fields=['exam', 'classroom', 'subject'],
                name='unique_paper_per_exam_class_subject',
            ),
        ]
        indexes = [models.Index(fields=['exam', 'classroom'])]

    def clean(self):
        super().clean()
        if self.max_marks == 0:
            raise ValidationError({'max_marks': 'Maximum marks must be more than zero.'})
        if self.pass_marks > self.max_marks:
            raise ValidationError({'pass_marks': 'Pass marks cannot exceed maximum marks.'})

    def __str__(self):
        return f'{self.exam.name} · {self.classroom} · {self.subject}'


class Mark(models.Model):
    """What one student scored on one paper."""

    paper = models.ForeignKey(ExamPaper, on_delete=models.CASCADE, related_name='marks')
    student = models.ForeignKey(
        'students.Student',
        on_delete=models.CASCADE,
        related_name='marks',
    )
    marks_obtained = models.DecimalField(
        max_digits=5,
        decimal_places=1,
        null=True,
        blank=True,
        help_text="Empty when the student was absent.",
    )
    is_absent = models.BooleanField(default=False)
    remarks = models.CharField(max_length=160, blank=True)
    entered_by = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='marks_entered',
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['paper', 'student'],
                name='unique_mark_per_paper_student',
            ),
        ]
        indexes = [models.Index(fields=['student'])]

    def __str__(self):
        shown = 'Absent' if self.is_absent else self.marks_obtained
        return f'{self.student} · {self.paper.subject}: {shown}'


class GradeBand(models.Model):
    """
    One step of the school's grading scale, e.g. A1 from 91%.

    Only the lower bound is stored; each band runs up to the next one. That
    makes gaps and overlaps impossible by construction.
    """

    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='grade_bands',
    )
    label = models.CharField(max_length=8, help_text="e.g. A1")
    min_percentage = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        help_text="Lowest percentage that earns this grade.",
    )
    description = models.CharField(max_length=60, blank=True, help_text="e.g. Outstanding")

    class Meta:
        ordering = ['-min_percentage']
        constraints = [
            models.UniqueConstraint(fields=['school', 'label'], name='unique_grade_label_per_school'),
            models.UniqueConstraint(fields=['school', 'min_percentage'], name='unique_grade_minimum_per_school'),
        ]

    def __str__(self):
        return f'{self.label} (from {self.min_percentage:g}%)'
