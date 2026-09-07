from rest_framework import permissions


class IsHomeworkAuthorized(permissions.BasePermission):
    """
    Role-aware permissions for Homework:
    - Admin: Full access within own school.
    - Teacher: Read & write within own school.
    - Parent: Read-only access strictly limited to classes where their children are enrolled.
    """

    message = "You do not have permission to perform this action."

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if user.is_superuser:
            return True

        if not user.school or not user.school.is_active:
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
        if obj.school != user.school:
            return False

        # Parent can only view homework for classes their children attend
        if user.role == 'PARENT':
            if request.method not in permissions.SAFE_METHODS:
                return False
            parent_classes = user.children.filter(
                is_active=True,
                class_enrolled__isnull=False,
            ).values_list('class_enrolled_id', flat=True)
            return obj.classroom_id in parent_classes

        # Teachers and Admins can view/manage school homework
        return True
