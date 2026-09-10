from django.db import models
from django.utils import timezone
from django.core.exceptions import ValidationError


class Homework(models.Model):
    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='homeworks',
        help_text="School this homework belongs to",
    )
    classroom = models.ForeignKey(
        'students.Class',
        on_delete=models.CASCADE,
        related_name='homeworks',
        help_text="Target class and section",
    )
    subject = models.CharField(max_length=100, help_text="Subject name (e.g. Mathematics)")
    title = models.CharField(max_length=255)
    description = models.TextField(
        blank=True,
        help_text="Detailed homework instructions or exercise numbers",
    )
    assigned_by = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='assigned_homeworks',
        help_text="Teacher who assigned this homework",
    )
    student = models.ForeignKey(
        'students.Student',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='individual_homeworks',
        help_text="Optional: specific student if homework is assigned individually",
    )
    assigned_date = models.DateField(default=timezone.localdate)
    due_date = models.DateField()
    attachment = models.FileField(
        upload_to='homework_attachments/',
        null=True,
        blank=True,
        help_text="Optional PDF or image attachment",
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-due_date', '-created_at']
        verbose_name = 'Homework'
        verbose_name_plural = 'Homeworks'
        indexes = [
            models.Index(fields=['school', 'classroom']),
            models.Index(fields=['school', 'due_date']),
            models.Index(fields=['school', 'assigned_date']),
            models.Index(fields=['school', 'subject']),
            models.Index(fields=['school', 'is_active']),
            models.Index(fields=['school', 'student']),
        ]

    def clean(self):
        super().clean()
        if self.classroom and hasattr(self, 'school_id') and self.school_id:
            if self.classroom.school_id != self.school_id:
                raise ValidationError({
                    'classroom': "Cannot assign homework to a class from another school."
                })
        if self.student and hasattr(self, 'school_id') and self.school_id:
            if self.student.school_id != self.school_id:
                raise ValidationError({
                    'student': "Cannot assign homework to a student from another school."
                })
            if self.classroom and self.student.class_enrolled_id and self.student.class_enrolled_id != self.classroom_id:
                raise ValidationError({
                    'student': "Selected student is not enrolled in the selected class."
                })

    def save(self, *args, **kwargs):
        if self.classroom and not self.school_id:
            self.school = self.classroom.school
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.subject}: {self.title} ({self.classroom})"
