from dataclasses import dataclass


@dataclass(frozen=True)
class SmsResult:
    """
    Outcome of one send.

    status: 'sent' | 'not_configured' | 'no_phone' | 'failed'
    detail: a human-readable reason safe to show an admin. Must never contain
            the message text or a password.
    """

    sent: bool
    status: str
    detail: str | None = None
    provider_message_id: str | None = None


class SmsProvider:
    """Interface every SMS provider adapter implements."""

    name = 'base'

    def send(self, phone_e164, message):  # pragma: no cover - interface
        raise NotImplementedError
