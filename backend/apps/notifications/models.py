from django.conf import settings
from django.db import models


class Notification(models.Model):
    class NotificationType(models.TextChoices):
        HOMEWORK = 'HOMEWORK', 'Homework'
        ANNOUNCEMENT = 'ANNOUNCEMENT', 'Announcement'
        ATTENDANCE = 'ATTENDANCE', 'Attendance'
        RESULT = 'RESULT', 'Exam result'
        MESSAGE = 'MESSAGE', 'Message'

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
    attendance = models.ForeignKey(
        'attendance.Attendance',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='notifications',
        help_text="Associated attendance record (if applicable)",
    )
    student = models.ForeignKey(
        'students.Student',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='notifications',
        help_text=(
            "The child this is about, for per-child events (attendance, a "
            "result, homework set for one student). Empty for class-wide and "
            "school-wide events, which concern every child they reach."
        ),
    )
    conversation = models.ForeignKey(
        'messaging.Conversation',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='notifications',
        help_text="Conversation with a new message (if applicable)",
    )
    exam = models.ForeignKey(
        'exams.Exam',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='notifications',
        help_text="Exam whose results this notification announces (if applicable)",
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
            # Attendance adds a row per child per school day, so the list has
            # to stay fast when filtered by type.
            models.Index(fields=['recipient', 'notification_type', '-created_at']),
        ]

    def __str__(self):
        return f"[{self.notification_type}] {self.title} -> {self.recipient.username}"


class DeviceToken(models.Model):
    """
    A phone that should receive push notifications for one user.

    A parent may have the app on two phones, and a phone may be handed to a
    different user, so tokens are unique per device and re-pointed at whoever
    signed in last rather than duplicated.
    """

    class Platform(models.TextChoices):
        ANDROID = 'ANDROID', 'Android'
        IOS = 'IOS', 'iOS'
        WEB = 'WEB', 'Web'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='device_tokens',
    )
    token = models.CharField(
        max_length=512,
        unique=True,
        help_text="Firebase registration token for this install",
    )
    platform = models.CharField(
        max_length=10,
        choices=Platform.choices,
        default=Platform.ANDROID,
    )
    device_name = models.CharField(max_length=120, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-last_seen_at']
        verbose_name = 'Device token'
        verbose_name_plural = 'Device tokens'
        indexes = [
            models.Index(fields=['user', 'is_active']),
        ]

    def __str__(self):
        return f'{self.user.username} · {self.platform} · {self.token[:12]}…'
