"""
Text messages to a user's mobile number.

No provider is wired in yet - the school will choose one (MSG91, Fast2SMS,
Twilio...). Until then `is_configured()` is False and nothing is sent; callers
fall back to showing the admin a one-time password once.

Adding a provider:
  1. Write a class with `name` and `send(self, phone_e164, message) -> SmsResult`
     in this package (see base.py).
  2. Register it in PROVIDERS below.
  3. Set SMS_PROVIDER and that provider's credentials in the environment.

Indian carriers only deliver SMS whose sender id and exact template text are
registered on the DLT platform (TRAI). Register the "temporary password"
template below before going live, or messages are silently dropped.
"""

from django.conf import settings

from .base import SmsProvider, SmsResult

PROVIDERS = {
    # 'msg91': Msg91Provider,   # added when the school picks a provider
}

TEMPORARY_PASSWORD_TEMPLATE = (
    '{school}: your app login is {login}. Temporary password: {password} . '
    'You will be asked to set your own password after signing in. Do not share this message.'
)


def configured_provider_name():
    return (getattr(settings, 'SMS_PROVIDER', '') or '').strip().lower()


def get_provider():
    """The active provider instance, or None when SMS is not set up."""
    name = configured_provider_name()
    provider_class = PROVIDERS.get(name)
    if provider_class is None:
        return None
    return provider_class()


def is_configured():
    return get_provider() is not None


def configuration_problem():
    """Why SMS cannot be sent, in words safe to show an admin - or None."""
    name = configured_provider_name()
    if not name:
        return 'SMS is not set up (SMS_PROVIDER is empty).'
    if name not in PROVIDERS:
        return f'SMS provider "{name}" is not available in this version.'
    return None


def send_temporary_password(user, password, school_name):
    """
    Sends a new account's or reset account's temporary password.

    Returns an SmsResult. Never raises, and never logs the password or the
    message text - only the outcome.
    """
    provider = get_provider()
    if provider is None:
        return SmsResult(sent=False, status='not_configured', detail=configuration_problem())
    if not user.phone_number:
        return SmsResult(sent=False, status='no_phone', detail='This account has no mobile number.')

    message = TEMPORARY_PASSWORD_TEMPLATE.format(
        school=school_name or 'School', login=user.phone_number, password=password,
    )
    try:
        return provider.send(f'+91{user.phone_number}', message)
    except Exception as exc:  # noqa: BLE001 - a provider failure must not fail account creation
        return SmsResult(sent=False, status='failed', detail=f'SMS provider error ({exc.__class__.__name__}).')


__all__ = [
    'SmsProvider', 'SmsResult', 'PROVIDERS', 'get_provider', 'is_configured',
    'configuration_problem', 'send_temporary_password',
]
