from django.db import models
from django.utils import timezone
from django.core.exceptions import ValidationError
from .validators import validate_announcement_attachment


class Announcement(models.Model):
    class Priority(models.TextChoices):
        NORMAL = 'NORMAL', 'Normal'
        IMPORTANT = 'IMPORTANT', 'Important'
        URGENT = 'URGENT', 'Urgent'

    class AudienceType(models.TextChoices):
        SCHOOL = 'SCHOOL', 'School'
        CLASS = 'CLASS', 'Class'

    school = models.ForeignKey(
        'schools.School',
        on_delete=models.CASCADE,
        related_name='announcements',
        help_text="School this announcement belongs to",
    )
    title = models.CharField(max_length=255)
    content = models.TextField(help_text="Announcement message or circular details")
    created_by = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_announcements',
        help_text="User who created this announcement",
    )
    published_at = models.DateTimeField(default=timezone.now)
    attachment = models.FileField(
        upload_to='announcements_attachments/',
        null=True,
        blank=True,
        validators=[validate_announcement_attachment],
        help_text="Optional circular PDF or image attachment",
    )
    priority = models.CharField(
        max_length=20,
        choices=Priority.choices,
        default=Priority.NORMAL,
    )
    audience_type = models.CharField(
        max_length=20,
        choices=AudienceType.choices,
        default=AudienceType.SCHOOL,
    )
    target_class = models.ForeignKey(
        'students.Class',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='announcements',
        help_text="Target class if audience_type is CLASS",
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-published_at', '-created_at']
        verbose_name = 'Announcement'
        verbose_name_plural = 'Announcements'

    def clean(self):
        super().clean()
        if self.audience_type == self.AudienceType.CLASS:
            if not self.target_class:
                raise ValidationError({'target_class': "Target class is required when audience type is CLASS."})
            if hasattr(self, 'school') and self.target_class.school_id != self.school_id:
                raise ValidationError({'target_class': "Target class must belong to the same school."})
        elif self.audience_type == self.AudienceType.SCHOOL:
            if self.target_class is not None:
                raise ValidationError({'target_class': "Target class must be null when audience type is SCHOOL."})

    def __str__(self):
        return f"[{self.priority}] {self.title} ({self.audience_type})"
