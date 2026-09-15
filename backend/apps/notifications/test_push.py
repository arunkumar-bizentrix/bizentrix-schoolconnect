"""
Firebase push: credential diagnostics, dead-token handling, and the promise
that no part of the service-account key is ever printed.

Nothing here talks to Google - urlopen and the OAuth exchange are mocked.
"""

import io
import json
import tempfile
import urllib.error
from pathlib import Path
from unittest import mock

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings

from apps.notifications import push
from apps.notifications.models import DeviceToken, Notification
from apps.notifications.services import NotificationService
from apps.schools.models import School

User = get_user_model()

FAKE_SECRET = 'FAKE-PRIVATE-KEY-MATERIAL-THAT-MUST-NEVER-BE-PRINTED'


def _key_file(directory, **overrides):
    data = {
        'type': 'service_account',
        'project_id': 'demo-project',
        'private_key_id': 'abc123',
        'private_key': f'-----BEGIN PRIVATE KEY-----\n{FAKE_SECRET}\n-----END PRIVATE KEY-----\n',
        'client_email': 'firebase-adminsdk@demo-project.iam.gserviceaccount.com',
    }
    data.update(overrides)
    path = Path(directory) / 'service-account.json'
    path.write_text(json.dumps(data), encoding='utf-8')
    return str(path)


def _http_error(code, body):
    return urllib.error.HTTPError('https://fcm', code, 'error', {}, io.BytesIO(json.dumps(body).encode()))


class _Ok:
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class ConfigurationTests(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_unset(self):
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=''):
            self.assertIn('not set', push.configuration_problem())
            self.assertFalse(push.is_configured())

    def test_missing_file(self):
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=str(Path(self.tmp.name) / 'nope.json')):
            self.assertIn('does not exist', push.configuration_problem())

    def test_not_json(self):
        path = Path(self.tmp.name) / 'broken.json'
        path.write_text('{not json', encoding='utf-8')
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=str(path)):
            self.assertIn('JSON', push.configuration_problem())

    def test_missing_fields(self):
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=_key_file(self.tmp.name, private_key='')):
            self.assertIn('private_key', push.configuration_problem())

    def test_wrong_kind_of_key(self):
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=_key_file(self.tmp.name, type='authorized_user')):
            self.assertIn('not a service-account', push.configuration_problem())

    def test_valid_file_outside_the_project(self):
        """The key may live anywhere - the recommended place is outside the repo."""
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=_key_file(self.tmp.name)):
            self.assertIsNone(push.configuration_problem())
            self.assertEqual(push.project_id(), 'demo-project')

    def test_problems_never_quote_the_key(self):
        for overrides in ({'type': 'wrong'}, {'client_email': ''}):
            with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=_key_file(self.tmp.name, **overrides)):
                self.assertNotIn(FAKE_SECRET, push.configuration_problem() or '')


class DeadTokenClassificationTests(TestCase):
    def test_unregistered_is_dead(self):
        body = {'error': {'details': [{'errorCode': 'UNREGISTERED'}]}}
        self.assertTrue(push._is_dead_token_error(404, body))
        self.assertTrue(push._is_dead_token_error(400, body))

    def test_malformed_registration_token_is_dead(self):
        body = {'error': {'message': 'The registration token is not a valid FCM registration token'}}
        self.assertTrue(push._is_dead_token_error(400, body))

    def test_credential_and_server_errors_are_not_the_tokens_fault(self):
        self.assertFalse(push._is_dead_token_error(401, {}))
        self.assertFalse(push._is_dead_token_error(403, {'error': {'message': 'SENDER_ID_MISMATCH'}}))
        self.assertFalse(push._is_dead_token_error(500, {}))
        self.assertFalse(push._is_dead_token_error(400, {'error': {'message': 'Invalid JSON payload'}}))


@override_settings(FIREBASE_SERVICE_ACCOUNT_FILE='')
class SendTests(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.settings_override = override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=_key_file(self.tmp.name))
        self.settings_override.enable()
        self.addCleanup(self.settings_override.disable)
        patcher = mock.patch.object(push, '_access_token', return_value='oauth-token')
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_success_and_validate_only_flag(self):
        captured = []

        def fake_urlopen(request, timeout=10):
            captured.append(json.loads(request.data))
            return _Ok()

        with mock.patch.object(push.urllib.request, 'urlopen', side_effect=fake_urlopen):
            result = push.send_to_tokens(['token-1'], 'Title', 'Body', validate_only=True)

        self.assertEqual(result['sent'], 1)
        self.assertTrue(captured[0]['validate_only'])
        self.assertEqual(captured[0]['message']['token'], 'token-1')

    def test_dead_token_is_reported_for_retirement(self):
        error = _http_error(404, {'error': {'details': [{'errorCode': 'UNREGISTERED'}]}})
        with mock.patch.object(push.urllib.request, 'urlopen', side_effect=error):
            result = push.send_to_tokens(['dead-token'], 'T', 'B')
        self.assertEqual(result['invalid_tokens'], ['dead-token'])

    def test_rejected_credential_stops_and_retires_nothing(self):
        calls = []

        def fake_urlopen(request, timeout=10):
            calls.append(1)
            raise _http_error(401, {'error': {'status': 'UNAUTHENTICATED'}})

        with mock.patch.object(push.urllib.request, 'urlopen', side_effect=fake_urlopen), \
                mock.patch.object(push, 'reset_token_cache') as reset:
            result = push.send_to_tokens(['a', 'b', 'c'], 'T', 'B')

        self.assertTrue(result['auth_failed'])
        self.assertEqual(result['invalid_tokens'], [])
        self.assertEqual(len(calls), 1, 'should stop after the first auth failure')
        reset.assert_called_once()

    def test_network_failure_retires_nothing(self):
        with mock.patch.object(push.urllib.request, 'urlopen', side_effect=OSError('offline')):
            result = push.send_to_tokens(['a'], 'T', 'B')
        self.assertEqual(result['invalid_tokens'], [])
        self.assertEqual(result['failed'], 1)


class RetirementTests(TestCase):
    def setUp(self):
        school = School.objects.create(name='Push Retire School', code='PRS01')
        self.parent = User.objects.create_user(username='pr_parent', password='x', role=User.Role.PARENT, school=school)
        self.live = DeviceToken.objects.create(user=self.parent, token='live-token-000000000000', platform='ANDROID')
        self.dead = DeviceToken.objects.create(user=self.parent, token='dead-token-000000000000', platform='ANDROID')
        self.note = Notification.objects.create(recipient=self.parent, notification_type='HOMEWORK', title='t', message='m')

    def test_dead_tokens_are_deactivated_not_live_ones(self):
        outcome = {'sent': 1, 'failed': 1, 'invalid_tokens': [self.dead.token], 'auth_failed': False}
        with mock.patch.object(push, 'send_to_tokens', return_value=outcome):
            NotificationService._push([self.note])
        self.dead.refresh_from_db()
        self.live.refresh_from_db()
        self.assertFalse(self.dead.is_active)
        self.assertTrue(self.live.is_active)

    def test_credential_failure_keeps_every_device(self):
        outcome = {'sent': 0, 'failed': 1, 'invalid_tokens': [], 'auth_failed': True}
        with mock.patch.object(push, 'send_to_tokens', return_value=outcome):
            NotificationService._push([self.note])
        self.assertEqual(DeviceToken.objects.filter(is_active=True).count(), 2)

    def test_a_retired_phone_that_registers_again_is_reactivated(self):
        self.dead.is_active = False
        self.dead.save()
        self.client.force_login(self.parent)
        from rest_framework.test import APIClient
        api = APIClient()
        api.force_authenticate(user=self.parent)
        res = api.post('/api/v1/notifications/register-device/', {'token': self.dead.token, 'platform': 'ANDROID'},
                       format='json')
        self.assertEqual(res.status_code, 200)
        self.dead.refresh_from_db()
        self.assertTrue(self.dead.is_active)


class CheckPushCommandTests(TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_unconfigured_fails_clearly(self):
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=''):
            with self.assertRaisesMessage(CommandError, 'not configured'):
                call_command('check_push', stdout=io.StringIO())

    def test_output_never_contains_the_key_or_a_full_token(self):
        out = io.StringIO()
        device = 'device-token-ABCDEFGHIJKLMNOPQRSTUVWXYZ-123456'
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=_key_file(self.tmp.name)), \
                mock.patch.object(push, '_access_token', return_value='oauth-token'), \
                mock.patch.object(push.urllib.request, 'urlopen', return_value=_Ok()):
            call_command('check_push', token=device, stdout=out)

        text = out.getvalue()
        self.assertIn('demo-project', text)
        self.assertIn('valid (nothing delivered)', text)
        self.assertNotIn(FAKE_SECRET, text)
        self.assertNotIn('BEGIN PRIVATE KEY', text)
        self.assertNotIn(device, text)
        self.assertIn('...123456', text)

    def test_refused_credential_reports_only_the_error_class(self):
        with override_settings(FIREBASE_SERVICE_ACCOUNT_FILE=_key_file(self.tmp.name)), \
                mock.patch.object(push, '_access_token', side_effect=ValueError(FAKE_SECRET)):
            with self.assertRaises(CommandError) as caught:
                call_command('check_push', stdout=io.StringIO())
        self.assertNotIn(FAKE_SECRET, str(caught.exception))
        self.assertIn('ValueError', str(caught.exception))
