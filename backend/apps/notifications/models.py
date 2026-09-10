from django.conf import settings
from django.db import models


class Notification(models.Model):
    class NotificationType(models.TextChoices):
        HOMEWORK = 'HOMEWORK', 'Homework'
        ANNOUNCEMENT = 'ANNOUNCEMENT', 'Announcement'

    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notifications',
        help_text="User who received this notification",
    )
    notification_type = models.CharField(
        max_length=20,
        choices=NotificationType.choices,
        help_text="Type of event that generated the notification",
    )
    title = models.CharField(max_length=255)
    message = models.TextField()
    homework = models.ForeignKey(
        'homework.Homework',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='notifications',
        help_text="Associated homework object (if applicable)",
    )
    announcement = models.ForeignKey(
        'announcements.Announcement',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='notifications',
        help_text="Associated announcement circular (if applicable)",
    )
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Notification'
        verbose_name_plural = 'Notifications'
        indexes = [
            models.Index(fields=['recipient', 'is_read']),
            models.Index(fields=['recipient', 'created_at']),
            models.Index(fields=['notification_type']),
        ]

    def __str__(self):
        return f"[{self.notification_type}] {self.title} -> {self.recipient.username}"
