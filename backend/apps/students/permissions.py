from rest_framework import permissions

from apps.schools.services import get_school_for

from .models import Class, Student, StudentClassEnrollment


class IsSchoolMember(permissions.BasePermission):
    """
    Authorization for Classes, Students and Enrollments.

    Roles (see docs/ARCHITECTURE.md - Role system):

    - ADMIN    Full management of classes, students, enrollments and the
               parent/teacher links between them.
    - TEACHER  Read-only. Object access is limited to classes assigned to
               them and to students enrolled in those classes. Teachers do
               not create, edit or delete classes or students, and cannot
               assign teachers to a class - that is admin territory.
               Their write access lives in Homework and Announcements.
    - PARENT   Read-only, limited to their own children and those children's
               classes.
    """

    message = "You do not have permission to perform this action."

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        if request.user.is_superuser:
            return True

        school = get_school_for(request.user)
        if school is None or not school.is_active:
            return False

        if request.method in permissions.SAFE_METHODS:
            return True

        # Class and Student management is administrative.
        return request.user.role == 'ADMIN'

    def has_object_permission(self, request, view, obj):
        if request.user.is_superuser:
            return True

        if hasattr(obj, 'school') and obj.school != get_school_for(request.user):
            return False

        if request.user.role == 'TEACHER':
            if request.method not in permissions.SAFE_METHODS:
                return False
            if isinstance(obj, Class):
                return obj.teachers.filter(id=request.user.id).exists()
            if isinstance(obj, Student):
                return bool(obj.class_enrolled and obj.class_enrolled.teachers.filter(id=request.user.id).exists())
            if isinstance(obj, StudentClassEnrollment):
                return bool(obj.classroom and obj.classroom.teachers.filter(id=request.user.id).exists())

        if request.user.role == 'PARENT':
            if request.method not in permissions.SAFE_METHODS:
                return False
            if isinstance(obj, Student):
                return obj.parents.filter(id=request.user.id).exists()
            if isinstance(obj, Class):
                parent_classes = request.user.children.filter(
                    is_active=True,
                    class_enrolled__isnull=False,
                ).values_list('class_enrolled_id', flat=True)
                return obj.id in parent_classes

        return True
