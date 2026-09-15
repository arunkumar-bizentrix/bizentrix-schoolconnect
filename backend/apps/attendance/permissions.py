from rest_framework import permissions

from apps.schools.services import get_school_for


class IsAttendanceAuthorized(permissions.BasePermission):
    """
    - ADMIN    marks and reads any class.
    - TEACHER  marks and reads only classes assigned to them.
    - PARENT   reads only their own children's records; never writes.
    """

    message = "You do not have permission to perform this action."

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if user.is_superuser:
            return True

        school = get_school_for(user)
        if not school or not school.is_active:
            return False

        if request.method in permissions.SAFE_METHODS:
            return True

        # Attendance is marked by whoever is in front of the class.
        return user.role in ('ADMIN', 'TEACHER')

    def has_object_permission(self, request, view, obj):
        user = request.user
        if user.is_superuser:
            return True
        if obj.school != get_school_for(user):
            return False

        if user.role == 'PARENT':
            return (
                request.method in permissions.SAFE_METHODS
                and obj.student.parents.filter(id=user.id).exists()
            )

        if user.role == 'TEACHER':
            if request.method in permissions.SAFE_METHODS:
                return obj.classroom.teachers.filter(id=user.id).exists()
            return obj.classroom.can_mark_attendance(user)

        return True
