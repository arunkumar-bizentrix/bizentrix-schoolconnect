import logging
from collections import defaultdict

from django.contrib.auth import get_user_model
from apps.students.models import Student
from . import push
from .models import DeviceToken, Notification

User = get_user_model()
logger = logging.getLogger('schoolconnect.notifications')


class NotificationService:
    """
    Creates in-app notifications and, where a device is registered, pushes them.

    Push is best-effort: it never fails the request that triggered it, and it
    is a silent no-op until Firebase is configured.
    """

    @classmethod
    def _push(cls, notifications):
        """
        Delivers the given notifications to whatever devices their recipients
        have registered. Grouped per recipient so one parent with two phones
        gets one message on each, not two on one.
        """
        try:
            if not notifications:
                return

            by_recipient = defaultdict(list)
            for notification in notifications:
                by_recipient[notification.recipient_id].append(notification)

            tokens_by_user = defaultdict(list)
            for row in DeviceToken.objects.filter(
                user_id__in=by_recipient.keys(), is_active=True
            ).values_list('user_id', 'token'):
                tokens_by_user[row[0]].append(row[1])

            dead_tokens = []
            for user_id, items in by_recipient.items():
                tokens = tokens_by_user.get(user_id)
                if not tokens:
                    continue

                # One phone alert per event, even if several rows were created.
                notification = items[0]
                result = push.send_to_tokens(
                    tokens,
                    title=notification.title,
                    body=notification.message,
                    data={
                        'notification_id': notification.id,
                        'type': notification.notification_type,
                        'homework_id': notification.homework_id or '',
                        'announcement_id': notification.announcement_id or '',
                        'attendance_id': notification.attendance_id or '',
                        'exam_id': notification.exam_id or '',
                    },
                )
                dead_tokens.extend(result['invalid_tokens'])

            # Retire tokens Firebase says no longer exist, so a wiped phone
            # does not keep costing a failed send on every notification.
            if dead_tokens:
                DeviceToken.objects.filter(token__in=dead_tokens).update(is_active=False)
        except Exception as exc:
            logger.error("Push fan-out failed: %s", exc.__class__.__name__)

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
            # due_display appends the time when the teacher set one, so the
            # parent sees "17 Sep 2026, 4:00 PM" rather than just the date.
            due_str = homework.due_display if homework.due_date else "Upcoming"

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
            cls._push(created)
            return created
        except Exception as exc:
            logger.error("Failed to create homework notifications: %s", exc)
            return []

    # Wording per status. A parent opening a phone notification wants the
    # answer in the first few words, not a sentence to parse.
    _ATTENDANCE_COPY = {
        'PRESENT': ('✅ {name} is in school',
                    '{name} was marked present in {classroom} today ({date}).'),
        'ABSENT': ('⚠️ {name} is absent',
                   '{name} was marked absent in {classroom} today ({date}).'),
        'LATE': ('🕒 {name} arrived late',
                 '{name} arrived late to {classroom} today ({date}).'),
        'EXCUSED': ('{name} is on approved leave',
                    '{name} was marked on approved leave from {classroom} '
                    'today ({date}).'),
    }

    @classmethod
    def create_attendance_notifications(cls, records):
        """
        Tells each parent whether their own child reached school.

        Only the given records notify, and the caller passes only rows whose
        status actually changed - correcting a mark from Absent to Late should
        send one update, while re-saving an unchanged register sends nothing.
        """
        try:
            records = [record for record in records if record is not None]
            if not records:
                return []

            notifications = []
            for record in records:
                title_template, message_template = cls._ATTENDANCE_COPY.get(
                    record.status,
                    ('{name} attendance updated',
                     '{name} attendance was updated for {classroom} ({date}).'),
                )
                context = {
                    'name': record.student.first_name or record.student.full_name,
                    'classroom': f'{record.classroom.name} - {record.classroom.section}',
                    'date': record.date.strftime('%d %b %Y'),
                }
                body = message_template.format(**context)
                if record.note:
                    body = f'{body} Note: {record.note}'

                for parent in record.student.parents.filter(is_active=True):
                    notifications.append(
                        Notification(
                            recipient=parent,
                            notification_type=Notification.NotificationType.ATTENDANCE,
                            title=title_template.format(**context),
                            message=body,
                            attendance=record,
                            is_read=False,
                        )
                    )

            if not notifications:
                return []

            created = Notification.objects.bulk_create(notifications)
            logger.info("Created %d attendance notifications", len(created))
            cls._push(created)
            return created
        except Exception as exc:
            logger.error("Failed to create attendance notifications: %s", exc)
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
            cls._push(created)
            return created
        except Exception as exc:
            logger.error("Failed to create announcement notifications: %s", exc)
            return []
