"""
Test settings for Bizentrix SchoolConnect.

Inherits everything from the normal settings module and overrides only what
makes the suite slow, non-deterministic, or dependent on external services.

Used automatically by `python manage.py test` (see manage.py). To run the
suite against a different settings module, pass --settings explicitly.
"""

from .settings import *  # noqa: F401,F403

# ---------------------------------------------------------------------------
# Speed: the production PBKDF2 hasher runs 600k iterations per password. Test
# setUp() methods create ~30 users per module and re-run per test method, which
# costs tens of minutes. Tests never verify hash strength, so use a cheap hasher.
# ---------------------------------------------------------------------------
PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.MD5PasswordHasher',
]

# ---------------------------------------------------------------------------
# Isolation from external services: no test may open an SMTP connection or
# call the Meta WhatsApp Cloud API, regardless of what .env happens to contain.
# Individual tests still override these when they need to assert on a specific
# delivery mode.
# ---------------------------------------------------------------------------
DEFAULT_FROM_EMAIL = 'test@schoolconnect.test'

WHATSAPP_ACCESS_TOKEN = None
WHATSAPP_PHONE_NUMBER_ID = None

# No push leaves the test suite, whatever the developer has configured locally.
FIREBASE_SERVICE_ACCOUNT_FILE = ''
PUSH_IN_BACKGROUND = False
SMS_PROVIDER = ''

# Throttling stays wired up (the views declare it explicitly) but the rates are
# lifted so they never interfere with functional assertions. The throttle tests
# pin low rates locally with @override_settings.
REST_FRAMEWORK = {  # noqa: F405
    **REST_FRAMEWORK,  # noqa: F405
    'DEFAULT_THROTTLE_RATES': {'auth': '10000/min', 'otp': '10000/min', 'messages': '10000/min'},
}

# Uploaded files from tests go to a throwaway folder, never the real media
# directory the development server serves.
import tempfile as _tempfile
from pathlib import Path as _Path

MEDIA_ROOT = _Path(_tempfile.mkdtemp(prefix='schoolconnect-test-media-'))
