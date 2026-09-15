"""
Accounts the school admin creates for its teachers and parents.

Nobody signs up as a teacher: the admin creates the account and hands over a
one-time password. That keeps a stranger who installs the app from joining
the school as staff.
"""

import re
import secrets

from django.db import transaction

from ..models import User

# No 0/O, 1/l/I: the password is read aloud or copied off a phone screen.
_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'

MANAGED_ROLES = (User.Role.TEACHER, User.Role.PARENT)


class AccountError(ValueError):
    """A request that cannot be honoured, with a message fit to show the admin."""


def generate_temporary_password():
    """Eight characters in two groups, e.g. ``Km7Q-p4Xz``."""
    raw = ''.join(secrets.choice(_ALPHABET) for _ in range(8))
    return f'{raw[:4]}-{raw[4:]}'


def normalize_phone(raw):
    digits = re.sub(r'\D', '', str(raw or ''))
    if len(digits) == 12 and digits.startswith('91'):
        digits = digits[2:]
    return digits


def split_name(full_name):
    parts = (full_name or '').strip().split(' ', 1)
    return parts[0], (parts[1] if len(parts) > 1 else '')


def unique_username(full_name, fallback='user'):
    base = re.sub(r'[^a-z0-9_]', '', (full_name or '').strip().lower().replace(' ', '_'))
    base = base[:30] or fallback
    username, suffix = base, 1
    while User.objects.filter(username=username).exists():
        suffix += 1
        username = f'{base}_{suffix}'
    return username


@transaction.atomic
def create_school_account(*, school, role, full_name, phone_number, email=''):
    """
    Returns ``(user, temporary_password)``. The password is not stored in
    plain text anywhere; this return value is the only time it exists.
    """
    if role not in MANAGED_ROLES:
        raise AccountError('Only teacher and parent accounts can be created here.')

    phone = normalize_phone(phone_number)
    if len(phone) != 10:
        raise AccountError('Enter a 10-digit mobile number.')

    email = (email or '').strip().lower()

    # The phone number is how this person signs in, so two accounts of the
    # same kind cannot share it.
    if User.objects.filter(role=role, phone_number=phone).exists():
        raise AccountError(
            f'A {role.lower()} with the mobile number {phone} already exists.'
        )
    if email and User.objects.filter(email__iexact=email).exists():
        raise AccountError(f'An account with the email {email} already exists.')

    first_name, last_name = split_name(full_name)
    if not first_name:
        raise AccountError('Enter the full name.')

    password = generate_temporary_password()
    user = User.objects.create_user(
        username=unique_username(full_name, fallback=role.lower()),
        password=password,
        first_name=first_name,
        last_name=last_name,
        email=email,
        phone_number=phone,
        role=role,
        school=school,
        is_active=True,
    )
    return user, password


def reset_temporary_password(user):
    """Issues a fresh one-time password; the old one stops working at once."""
    if user.role not in MANAGED_ROLES:
        raise AccountError('Only teacher and parent passwords can be reset here.')
    password = generate_temporary_password()
    user.set_password(password)
    user.save(update_fields=['password'])
    return password
