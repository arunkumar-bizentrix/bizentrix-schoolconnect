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

        if not user.school:
            from apps.schools.models import School
            user.school = School.objects.first()
            if user.school:
                user.save(update_fields=['school'])

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

        if not user.school:
            from apps.schools.models import School
            user.school = School.objects.first()

        # Tenant boundary check
        if obj.school != user.school:
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
