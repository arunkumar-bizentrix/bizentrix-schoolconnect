from rest_framework import permissions

from apps.schools.services import get_school_for


class IsHomeworkAuthorized(permissions.BasePermission):
    """
    Role-aware permissions for Homework:
    - Admin: full access within the school.
    - Teacher: read and write, limited to classes assigned to them.
    - Parent: read-only, limited to homework for their children's classes
      or addressed to one of their children individually.
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

        # Read permissions allowed for all authenticated school members
        if request.method in permissions.SAFE_METHODS:
            return True

        # Write permissions (POST, PUT, PATCH, DELETE) restricted to Teachers and Admins
        return user.role in ['ADMIN', 'TEACHER']

    def has_object_permission(self, request, view, obj):
        user = request.user
        if user.is_superuser:
            return True

        # Tenant boundary check
        if obj.school != get_school_for(user):
            return False

        # Parent can only view homework for classes their children attend or assigned to their child
        if user.role == 'PARENT':
            if request.method not in permissions.SAFE_METHODS:
                return False
            children = user.children.filter(is_active=True)
            parent_classes = children.filter(
                class_enrolled__isnull=False,
            ).values_list('class_enrolled_id', flat=True)
            children_ids = children.values_list('id', flat=True)
            return (obj.classroom_id in parent_classes and obj.student_id is None) or (obj.student_id in children_ids)

        # Teacher can only view/manage homework for their assigned classes
        if user.role == 'TEACHER':
            return obj.classroom.teachers.filter(id=user.id).exists()

        # Admins can view/manage school homework
        return True
