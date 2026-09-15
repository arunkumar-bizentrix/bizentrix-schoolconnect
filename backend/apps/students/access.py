"""
Who may look at one student's records.

Shared by the report card, its PDF and the student profile, so the rules can
never drift apart between them.
"""

from django.db.models import Q
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError

from apps.schools.services import get_school_for

from .models import Class, Student


def _is_admin(user):
    return user.is_superuser or user.role == 'ADMIN'


def student_for_report(request, student_id):
    """
    The one place that decides whose report card a user may open, shared by
    the JSON report card and the PDF so the two can never disagree.

    - Admin: any student of the school.
    - Teacher: students of a class they teach, or who have marks in one.
    - Parent: their own children only.
    The student is always looked up inside the caller's school, so an id from
    another school is simply not found.
    """
    user = request.user
    if not student_id:
        raise ValidationError({'student_id': 'Choose a student.'})

    students = Student.objects.select_related('class_enrolled', 'school')
    if not (user.is_superuser and not user.school):
        students = students.filter(school=get_school_for(user))
    student = students.filter(id=student_id).first()
    if student is None:
        raise NotFound('Student not found.')

    if user.role == 'PARENT':
        if not student.parents.filter(id=user.id).exists():
            raise PermissionDenied('You can only see your own children.')
    elif user.role == 'TEACHER':
        teaches = Class.objects.filter(teachers=user).filter(
            Q(id=student.class_enrolled_id) | Q(exam_papers__marks__student=student)
        ).exists()
        if not teaches:
            raise PermissionDenied('You can only see students of classes you teach.')
    elif not _is_admin(user):
        raise PermissionDenied()
    return student
