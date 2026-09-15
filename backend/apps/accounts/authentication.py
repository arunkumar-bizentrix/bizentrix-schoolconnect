"""
JWT authentication that also enforces "set your own password first".

A user signed in with a temporary password may only look at their profile,
change the password, and sign out. Everything else answers 403 with the code
`password_change_required` - the rule is enforced here, not by hiding screens
in the app.
"""

from rest_framework import exceptions, status
from rest_framework_simplejwt.authentication import JWTAuthentication

ALLOWED_WHILE_TEMPORARY = (
    ('GET', '/api/v1/auth/me/'),
    ('POST', '/api/v1/auth/change-password/'),
    ('POST', '/api/v1/notifications/register-device/'),
    ('DELETE', '/api/v1/notifications/register-device/'),
)


class PasswordChangeRequired(exceptions.APIException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Set your own password before continuing.'
    default_code = 'password_change_required'


class SchoolJWTAuthentication(JWTAuthentication):
    def authenticate(self, request):
        result = super().authenticate(request)
        if result is None:
            return None
        user, token = result
        if getattr(user, 'must_change_password', False):
            if (request.method, request.path) not in ALLOWED_WHILE_TEMPORARY:
                raise PasswordChangeRequired()
        return user, token
