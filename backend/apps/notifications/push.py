"""
Firebase Cloud Messaging delivery.

An in-app notification is only seen if the parent happens to open the app, and
nobody opens a school app daily on their own. This is what makes the phone
actually buzz.

The service is deliberately safe to run **without** Firebase configured: until
the school drops in a service-account file, every send is a no-op that logs and
returns, so the rest of the product keeps working. Nothing here ever raises
into a request.
"""

import json
import logging
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from django.conf import settings

logger = logging.getLogger('schoolconnect.push')

FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
FCM_ENDPOINT = 'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send'

# Access tokens last an hour; cache one rather than re-signing per message.
_token_cache = {'value': None, 'expires_at': 0.0}
_token_lock = threading.Lock()


def _credentials_path():
    configured = getattr(settings, 'FIREBASE_SERVICE_ACCOUNT_FILE', '') or ''
    if not configured:
        return None
    path = configured if os.path.isabs(configured) else os.path.join(
        settings.BASE_DIR, configured
    )
    return path if os.path.exists(path) else None


def is_configured():
    """Whether push can actually be delivered right now."""
    return _credentials_path() is not None


REQUIRED_KEYS = ('type', 'project_id', 'private_key', 'client_email')


def configuration_problem():
    """
    Why push is not usable, in words safe to print - or None when it is.

    Never includes any part of the credential: only whether the file exists,
    parses, and has the fields a service account must have.
    """
    configured = getattr(settings, 'FIREBASE_SERVICE_ACCOUNT_FILE', '') or ''
    if not configured:
        return 'FIREBASE_SERVICE_ACCOUNT_FILE is not set.'
    if _credentials_path() is None:
        return 'FIREBASE_SERVICE_ACCOUNT_FILE points to a file that does not exist.'
    try:
        credentials = _load_credentials()
    except (OSError, ValueError):
        return 'The service-account file could not be read as JSON.'
    missing = [key for key in REQUIRED_KEYS if not credentials.get(key)]
    if missing:
        return f"The service-account file is missing: {', '.join(missing)}."
    if credentials.get('type') != 'service_account':
        return 'The file is not a service-account key.'
    return None


def project_id():
    """The Firebase project the credential belongs to (not secret)."""
    try:
        credentials = _load_credentials()
    except (OSError, ValueError):
        return None
    return (credentials or {}).get('project_id')


def reset_token_cache():
    """Forget the cached OAuth token - after swapping in a rotated key."""
    with _token_lock:
        _token_cache['value'] = None
        _token_cache['expires_at'] = 0.0


def _load_credentials():
    path = _credentials_path()
    if path is None:
        return None
    with open(path, 'r', encoding='utf-8') as handle:
        return json.load(handle)


def _access_token():
    """
    Exchanges the service-account key for a short-lived OAuth token.

    Uses google-auth when it is installed; otherwise signs the JWT directly so
    that push works without pulling in another dependency.
    """
    with _token_lock:
        if _token_cache['value'] and _token_cache['expires_at'] > time.time() + 60:
            return _token_cache['value']

        credentials = _load_credentials()
        if credentials is None:
            return None

        try:
            from google.oauth2 import service_account  # type: ignore
            from google.auth.transport.requests import Request  # type: ignore

            scoped = service_account.Credentials.from_service_account_info(
                credentials, scopes=[FCM_SCOPE]
            )
            scoped.refresh(Request())
            _token_cache['value'] = scoped.token
            _token_cache['expires_at'] = time.time() + 3300
            return scoped.token
        except ImportError:
            pass

        token = _sign_jwt_for_token(credentials)
        if token:
            _token_cache['value'] = token
            _token_cache['expires_at'] = time.time() + 3300
        return token


def _sign_jwt_for_token(credentials):
    """Fallback path: build and exchange a signed JWT with no google-auth."""
    try:
        import base64

        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
    except ImportError:
        logger.error(
            "Push is configured but neither google-auth nor cryptography is "
            "installed; cannot sign the token."
        )
        return None

    def b64(raw):
        return base64.urlsafe_b64encode(raw).rstrip(b'=')

    issued_at = int(time.time())
    header = b64(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    claims = b64(json.dumps({
        'iss': credentials['client_email'],
        'scope': FCM_SCOPE,
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': issued_at,
        'exp': issued_at + 3600,
    }).encode())

    signing_input = header + b'.' + claims
    private_key = serialization.load_pem_private_key(
        credentials['private_key'].encode(), password=None
    )
    signature = b64(private_key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256()))
    assertion = (signing_input + b'.' + signature).decode()

    body = urllib.parse.urlencode({
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
    }).encode()

    request = urllib.request.Request(
        'https://oauth2.googleapis.com/token',
        data=body,
        headers={'Content-Type': 'application/x-www-form-urlencoded'},
        method='POST',
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode()).get('access_token')


# FCM v1 error codes meaning the token itself is dead and should be retired.
_DEAD_TOKEN_CODES = {'UNREGISTERED'}


def _is_dead_token_error(http_status, payload):
    """
    Only retire a token when Firebase says the *token* is the problem.

    401/403 mean our credential is wrong (for example an old, revoked key) and
    500s are Firebase's problem: retiring every parent's phone on either would
    silently end push for the whole school.
    """
    error = (payload or {}).get('error', {}) if isinstance(payload, dict) else {}
    codes = {
        detail.get('errorCode')
        for detail in error.get('details', []) or []
        if isinstance(detail, dict)
    }
    if codes & _DEAD_TOKEN_CODES:
        return True
    if http_status == 404:
        return True
    if http_status == 400 and 'registration token' in str(error.get('message', '')).lower():
        return True
    return False


def send_to_tokens(tokens, title, body, data=None, validate_only=False):
    """
    Delivers one message to a list of device tokens.

    Returns ``{'sent': int, 'failed': int, 'invalid_tokens': [...],
    'auth_failed': bool}``. Tokens Firebase reports as dead come back in
    ``invalid_tokens`` so the caller can retire them - a phone that was wiped
    keeps its row forever otherwise.

    ``validate_only`` asks Firebase to check the message and token without
    delivering anything - how `manage.py check_push` tests a real device.

    Never raises: a failed push must not fail the request that triggered it.
    """
    result = {'sent': 0, 'failed': 0, 'invalid_tokens': [], 'auth_failed': False}
    tokens = [token for token in tokens if token]
    if not tokens:
        return result

    if not is_configured():
        logger.info(
            "Push not configured; skipped %d message(s). Add a Firebase "
            "service-account file to enable delivery.", len(tokens)
        )
        return result

    try:
        access_token = _access_token()
        credentials = _load_credentials()
        if not access_token or not credentials:
            return result

        url = FCM_ENDPOINT.format(project_id=credentials['project_id'])
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json; UTF-8',
        }

        # The v1 API sends one token per call. A class is tens of parents, not
        # thousands, so a simple loop is honest and keeps error handling per
        # token; batching belongs here only if that changes.
        for token in tokens:
            message = {
                'validate_only': bool(validate_only),
                'message': {
                    'token': token,
                    'notification': {'title': title, 'body': body},
                    'data': {str(k): str(v) for k, v in (data or {}).items()},
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'channel_id': 'schoolconnect_default',
                            'default_sound': True,
                        },
                    },
                }
            }
            request = urllib.request.Request(
                url,
                data=json.dumps(message).encode('utf-8'),
                headers=headers,
                method='POST',
            )
            try:
                with urllib.request.urlopen(request, timeout=10):
                    result['sent'] += 1
            except urllib.error.HTTPError as exc:
                result['failed'] += 1
                try:
                    payload = json.loads(exc.read().decode('utf-8') or '{}')
                except (ValueError, OSError):
                    payload = {}
                if exc.code in (401, 403):
                    # The credential is rejected; every further send would fail
                    # the same way. Stop, and drop the cached token so a
                    # rotated key is picked up on the next attempt.
                    result['auth_failed'] = True
                    reset_token_cache()
                    logger.error("Push credential rejected by Firebase (HTTP %s).", exc.code)
                    break
                if _is_dead_token_error(exc.code, payload):
                    result['invalid_tokens'].append(token)
                logger.warning("Push rejected for one device: HTTP %s", exc.code)
            except Exception as exc:  # network hiccup, DNS, timeout
                result['failed'] += 1
                logger.warning("Push failed for one device: %s", exc.__class__.__name__)

        return result
    except Exception as exc:
        logger.error("Push delivery failed: %s", exc.__class__.__name__)
        return result
