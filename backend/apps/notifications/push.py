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


def send_to_tokens(tokens, title, body, data=None):
    """
    Delivers one message to a list of device tokens.

    Returns ``{'sent': int, 'failed': int, 'invalid_tokens': [...]}``. Tokens
    Firebase reports as dead come back in ``invalid_tokens`` so the caller can
    retire them - a phone that was wiped keeps its row forever otherwise.

    Never raises: a failed push must not fail the request that triggered it.
    """
    result = {'sent': 0, 'failed': 0, 'invalid_tokens': []}
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
                # 404 UNREGISTERED / 400 INVALID_ARGUMENT mean the token is dead.
                if exc.code in (400, 404):
                    result['invalid_tokens'].append(token)
                logger.warning("Push rejected for one device: HTTP %s", exc.code)
            except Exception as exc:  # network hiccup, DNS, timeout
                result['failed'] += 1
                logger.warning("Push failed for one device: %s", exc.__class__.__name__)

        return result
    except Exception as exc:
        logger.error("Push delivery failed: %s", exc.__class__.__name__)
        return result
