from django.db import models
from django.utils import timezone


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
    assigned_date = models.DateField(default=timezone.now)
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

    def __str__(self):
        return f"{self.subject}: {self.title} ({self.classroom})"
