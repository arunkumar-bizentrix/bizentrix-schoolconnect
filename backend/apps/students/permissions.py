from rest_framework import permissions


class IsSchoolMember(permissions.BasePermission):
    """
    Ensures the user is authenticated and belongs to an active school.
    Enforces strict tenant isolation at the object level.
    """

    message = "You must be associated with an active school to perform this action."

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        if request.user.is_superuser:
            return True

        return request.user.school is not None and request.user.school.is_active

    def has_object_permission(self, request, view, obj):
        if request.user.is_superuser:
            return True

        return hasattr(obj, 'school') and obj.school == request.user.school
