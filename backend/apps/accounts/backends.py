"""
Sign-in by the identifier people actually remember.

An admin creates a teacher from their name and phone number; nobody at the
school will remember a generated username like ``priya_sharma_2``. This backend
lets the same password sign in with the username, the 10-digit phone number or
the email address.
"""

import re

from django.contrib.auth.backends import ModelBackend
from django.db.models import Q

from .models import User


def _phone_digits(value):
    digits = re.sub(r'\D', '', value)
    if len(digits) == 12 and digits.startswith('91'):
        digits = digits[2:]
    return digits


class SchoolIdentifierBackend(ModelBackend):
    """
    Username first, exactly as Django does. Only when no account has that
    username does it look for a phone or email match.

    A phone number can belong to more than one account - a parent who is also
    a teacher, say. Every match is tried against the password, so the right
    account is the one whose password was typed; parents imported from a roll
    sheet have no usable password and can never be picked up by accident.
    """

    def authenticate(self, request, username=None, password=None, **kwargs):
        if username is None:
            username = kwargs.get(User.USERNAME_FIELD)
        if not username or password is None:
            return None

        identifier = str(username).strip()

        if User.objects.filter(username=identifier).exists():
            return super().authenticate(
                request, username=identifier, password=password, **kwargs
            )

        lookup = Q()
        if '@' in identifier:
            lookup = Q(email__iexact=identifier)
        else:
            digits = _phone_digits(identifier)
            if len(digits) == 10:
                lookup = Q(phone_number=digits)

        if not lookup:
            # Keep response time uniform with a real password check, so a
            # probe cannot tell unknown identifiers from wrong passwords.
            User().set_password(password)
            return None

        for candidate in User.objects.filter(lookup, is_active=True):
            if candidate.check_password(password) and self.user_can_authenticate(candidate):
                return candidate
        return None
