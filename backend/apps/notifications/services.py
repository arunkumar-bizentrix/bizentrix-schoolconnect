import logging
from django.contrib.auth import get_user_model
from apps.students.models import Student
from .models import Notification

User = get_user_model()
logger = logging.getLogger('schoolconnect.notifications')


class NotificationService:
    @classmethod
    def create_homework_notifications(cls, homework):
        """
        Dispatches in-app notifications to parents when homework is created.
        Enforces deduplication: if one parent has multiple children in the target class,
        only one notification is generated.
        """
        try:
            if not homework or not homework.is_active:
                return []

            parent_users = set()

            # If individual homework for a specific student
            if homework.student:
                for parent in homework.student.parents.filter(is_active=True):
                    parent_users.add(parent)
            elif homework.classroom:
                # Class-wide homework: gather all unique parents of students in this class
                students = Student.objects.filter(
                    class_enrolled=homework.classroom,
                    is_active=True,
                ).prefetch_related('parents')

                for student in students:
                    for parent in student.parents.filter(is_active=True):
                        parent_users.add(parent)

            if not parent_users:
                return []

            class_label = f"{homework.classroom.name} - {homework.classroom.section}" if homework.classroom else "Class"
            due_str = homework.due_date.strftime('%d %b %Y') if homework.due_date else "Upcoming"

            notifications = [
                Notification(
                    recipient=parent,
                    notification_type=Notification.NotificationType.HOMEWORK,
                    title=f"New Homework: {homework.subject}",
                    message=f"New {homework.subject} homework '{homework.title}' has been assigned for {class_label}. Due date: {due_str}.",
                    homework=homework,
                    is_read=False,
                )
                for parent in parent_users
            ]

            created = Notification.objects.bulk_create(notifications)
            logger.info("Created %d homework notifications for homework ID %d", len(created), homework.id)
            return created
        except Exception as exc:
            logger.error("Failed to create homework notifications: %s", exc)
            return []

    @classmethod
    def create_announcement_notifications(cls, announcement):
        """
        Dispatches in-app notifications to parents when an announcement is published.
        - CLASS announcement: Notifies unique parents of students in target_class.
        - SCHOOL announcement: Notifies all active parent accounts in the school.
        """
        try:
            if not announcement or not announcement.is_active:
                return []

            parent_users = set()

            if announcement.audience_type == 'CLASS' and announcement.target_class:
                students = Student.objects.filter(
                    class_enrolled=announcement.target_class,
                    is_active=True,
                ).prefetch_related('parents')

                for student in students:
                    for parent in student.parents.filter(is_active=True):
                        parent_users.add(parent)
            elif announcement.audience_type == 'SCHOOL':
                school = announcement.school
                parents = User.objects.filter(
                    school=school,
                    role=User.Role.PARENT,
                    is_active=True,
                )
                for parent in parents:
                    parent_users.add(parent)

            if not parent_users:
                return []

            is_urgent = getattr(announcement, 'priority', '') == 'URGENT'
            title_prefix = "⚠️ Urgent Notice" if is_urgent else "📢 School Circular"
            full_title = f"{title_prefix}: {announcement.title}"

            snippet = announcement.content.strip()
            if len(snippet) > 160:
                snippet = snippet[:157] + '...'

            notifications = [
                Notification(
                    recipient=parent,
                    notification_type=Notification.NotificationType.ANNOUNCEMENT,
                    title=full_title,
                    message=snippet or announcement.title,
                    announcement=announcement,
                    is_read=False,
                )
                for parent in parent_users
            ]

            created = Notification.objects.bulk_create(notifications)
            logger.info("Created %d announcement notifications for announcement ID %d", len(created), announcement.id)
            return created
        except Exception as exc:
            logger.error("Failed to create announcement notifications: %s", exc)
            return []
