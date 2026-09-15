"""
Who may message whom. Enforced on every send, not only in the contact list.

- Admin    <-> any active teacher or parent of the school.
- Teacher  <-> parents of students in a class the teacher is assigned to.
- A parent may *start* a conversation only with an admin or with the class
  teacher of one of their children; they may reply to any teacher of their
  child who wrote to them.
Nobody messages across schools, messages an inactive account, or messages
someone the relationship no longer covers (a teacher moved off the class).
"""

from django.contrib.auth import get_user_model
from django.db.models import Q

from apps.students.models import Class, Student

User = get_user_model()

ADMIN, TEACHER, PARENT = 'ADMIN', 'TEACHER', 'PARENT'


def _teaches_a_child_of(teacher, parent):
    return Student.objects.filter(
        parents=parent, is_active=True, class_enrolled__teachers=teacher,
    ).exists()


def _is_class_teacher_of_a_child_of(teacher, parent):
    return Student.objects.filter(
        parents=parent, is_active=True, class_enrolled__class_teacher=teacher,
    ).exists()


def related(a, b):
    """Whether these two may be in a conversation at all."""
    if a is None or b is None or a.pk == b.pk:
        return False
    if not (a.is_active and b.is_active) or a.school_id is None or a.school_id != b.school_id:
        return False
    roles = {a.role, b.role}
    if ADMIN in roles:
        return roles <= {ADMIN, TEACHER, PARENT} and roles != {ADMIN}
    if roles == {TEACHER, PARENT}:
        teacher, parent = (a, b) if a.role == TEACHER else (b, a)
        return _teaches_a_child_of(teacher, parent)
    return False


def can_start(sender, recipient):
    if not related(sender, recipient):
        return False
    if sender.role == PARENT and recipient.role == TEACHER:
        return _is_class_teacher_of_a_child_of(recipient, sender)
    return True


def can_send(user, conversation):
    if user.pk not in conversation.participant_ids():
        return False
    return related(user, conversation.other_participant(user))


def contacts_for(user):
    """People this user may start a conversation with."""
    people = User.objects.filter(school_id=user.school_id, is_active=True).exclude(pk=user.pk)
    admins = Q(role=ADMIN)
    if user.role == ADMIN:
        return people.filter(role__in=[TEACHER, PARENT])
    if user.role == TEACHER:
        classes = Class.objects.filter(teachers=user)
        return people.filter(admins | Q(role=PARENT, children__class_enrolled__in=classes,
                                        children__is_active=True)).distinct()
    if user.role == PARENT:
        return people.filter(admins | Q(role=TEACHER, homeroom_classes__students__parents=user,
                                        homeroom_classes__students__is_active=True)).distinct()
    return people.none()
