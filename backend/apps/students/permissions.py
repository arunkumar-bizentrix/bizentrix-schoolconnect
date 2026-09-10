from rest_framework import permissions
from .models import Class, Student, StudentClassEnrollment


class IsSchoolMember(permissions.BasePermission):
    """
    Ensures the user is authenticated and belongs to an active school.
    Enforces role permissions:
    - Classes & Students write operations (POST, PUT, PATCH, DELETE) restricted to Admins.
    - Teachers: Safe methods only.
      Object level:
        - Class: Teacher can only access classes assigned to them.
        - Student: Teacher can only access students enrolled in classes assigned to them.
    - Parents: Safe methods only.
      Object level:
        - Student: Parent can only access their own children.
    """

    message = "You do not have permission to perform this action."

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        if request.user.is_superuser:
            return True

        if not request.user.school:
            from apps.schools.models import School
            request.user.school = School.objects.first()
            if request.user.school:
                request.user.save(update_fields=['school'])

        if not (request.user.school is not None and request.user.school.is_active):
            return False

        if request.method in permissions.SAFE_METHODS:
            return True

        # Write permissions (POST, PUT, PATCH, DELETE) allowed for ADMIN and TEACHER
        # (Parents are strictly read-only for safe methods)
        return request.user.role in ['ADMIN', 'TEACHER']

    def has_object_permission(self, request, view, obj):
        if request.user.is_superuser:
            return True

        if not request.user.school:
            from apps.schools.models import School
            request.user.school = School.objects.first()

        if hasattr(obj, 'school') and obj.school != request.user.school:
            return False

        if request.user.role == 'TEACHER':
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
