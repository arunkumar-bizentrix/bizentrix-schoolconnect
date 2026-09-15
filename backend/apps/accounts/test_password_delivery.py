"""
Temporary passwords: how they reach the person, how long they live, and the
server-enforced "choose your own password" step.
"""

from datetime import timedelta
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient, APITestCase

from apps.accounts.services import sms
from apps.accounts.services.sms import SmsProvider, SmsResult
from apps.schools.models import School

User = get_user_model()


class RecordingProvider(SmsProvider):
    name = 'recording'
    sent = []

    def send(self, phone_e164, message):
        RecordingProvider.sent.append((phone_e164, message))
        return SmsResult(sent=True, status='sent', provider_message_id='msg-1')


class BrokenProvider(SmsProvider):
    name = 'broken'

    def send(self, phone_e164, message):
        raise ConnectionError('provider down')


class PasswordDeliveryTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name='Vivekananda School, Bagalur', code='PWD01')
        self.admin = User.objects.create_user(username='pw_admin', password='Admin@12345', role=User.Role.ADMIN,
                                              school=self.school)
        RecordingProvider.sent = []

    def create_teacher(self, phone='9876500001'):
        self.client.force_authenticate(user=self.admin)
        return self.client.post('/api/v1/auth/staff/', {
            'full_name': 'Priya Sharma', 'phone_number': phone, 'role': 'TEACHER',
        }, format='json')

    # -- delivery -----------------------------------------------------------------------

    def test_without_sms_the_admin_sees_the_password_once_marked_not_sent(self):
        res = self.create_teacher()
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['delivery'], 'shown_to_admin')
        self.assertEqual(res.data['sms_status'], 'not_configured')
        self.assertIn('not set up', res.data['sms_detail'])
        self.assertTrue(res.data['temporary_password'])

        user = User.objects.get(phone_number='9876500001')
        self.assertTrue(user.must_change_password)
        self.assertAlmostEqual(user.temporary_password_expires_at, timezone.now() + timedelta(days=7),
                               delta=timedelta(minutes=1))

    @override_settings(SMS_PROVIDER='recording')
    def test_with_sms_the_password_is_sent_and_not_returned(self):
        with mock.patch.dict(sms.PROVIDERS, {'recording': RecordingProvider}):
            with self.assertLogs('schoolconnect.accounts', level='INFO') as logs:
                res = self.create_teacher()

        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['delivery'], 'sms')
        self.assertNotIn('temporary_password', res.data)

        self.assertEqual(len(RecordingProvider.sent), 1)
        phone, message = RecordingProvider.sent[0]
        self.assertEqual(phone, '+919876500001')
        self.assertIn('9876500001', message)
        self.assertIn('Vivekananda School, Bagalur', message)

        # The password is in the SMS and nowhere else: not the response, not the logs.
        password = message.split('Temporary password: ')[1].split(' ')[0]
        self.assertTrue(len(password) >= 8)
        self.assertNotIn(password, str(res.data))
        self.assertNotIn(password, '\n'.join(logs.output))

        # And it works.
        signed_in = APIClient().post('/api/v1/auth/token/', {'username': '9876500001', 'password': password},
                                     format='json')
        self.assertEqual(signed_in.status_code, status.HTTP_200_OK)

    @override_settings(SMS_PROVIDER='broken')
    def test_provider_failure_falls_back_to_showing_the_admin(self):
        with mock.patch.dict(sms.PROVIDERS, {'broken': BrokenProvider}):
            res = self.create_teacher()
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['delivery'], 'shown_to_admin')
        self.assertEqual(res.data['sms_status'], 'failed')
        self.assertIn('ConnectionError', res.data['sms_detail'])
        self.assertTrue(res.data['temporary_password'])

    @override_settings(SMS_PROVIDER='someone-elses-gateway')
    def test_unknown_provider_is_reported_not_faked(self):
        res = self.create_teacher()
        self.assertEqual(res.data['sms_status'], 'not_configured')
        self.assertIn('not available', res.data['sms_detail'])

    def test_the_log_never_contains_the_password(self):
        with self.assertLogs('schoolconnect.accounts', level='INFO') as logs:
            res = self.create_teacher()
        self.assertNotIn(res.data['temporary_password'], '\n'.join(logs.output))


class TemporaryPasswordLifecycleTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name='Lifecycle School', code='PWD02')
        self.admin = User.objects.create_user(username='lc_admin', password='Admin@12345', role=User.Role.ADMIN,
                                              school=self.school)
        self.admin_client = APIClient()
        self.admin_client.force_authenticate(user=self.admin)
        res = self.admin_client.post('/api/v1/auth/staff/', {
            'full_name': 'Ravi Kumar', 'phone_number': '9123400001', 'role': 'PARENT',
        }, format='json')
        self.person_id = res.data['account']['id']
        self.temporary = res.data['temporary_password']

    def sign_in(self, password=None, identifier='9123400001'):
        return APIClient().post('/api/v1/auth/token/', {'username': identifier, 'password': password or self.temporary},
                                format='json')

    def bearer(self, access):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f'Bearer {access}')
        return client

    def test_sign_in_says_a_new_password_is_required(self):
        res = self.sign_in()
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['must_change_password'])

    def test_everything_but_profile_and_change_is_blocked_until_changed(self):
        client = self.bearer(self.sign_in().data['access'])

        me = client.get('/api/v1/auth/me/')
        self.assertEqual(me.status_code, status.HTTP_200_OK)
        self.assertTrue(me.data['must_change_password'])

        for url in ('/api/v1/students/', '/api/v1/notifications/', '/api/v1/parent/today/', '/api/v1/classes/'):
            res = client.get(url)
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN, url)
            self.assertEqual(res.data['detail'].code, 'password_change_required', url)
        self.assertEqual(client.patch('/api/v1/auth/me/', {'first_name': 'X'}, format='json').status_code,
                         status.HTTP_403_FORBIDDEN)
        # Registering this phone for push and signing out still work.
        device = client.post('/api/v1/notifications/register-device/',
                             {'token': 'temporary-password-phone-token-000', 'platform': 'ANDROID'}, format='json')
        self.assertIn(device.status_code, (status.HTTP_200_OK, status.HTTP_201_CREATED))
        gone = client.delete('/api/v1/notifications/register-device/',
                             {'token': 'temporary-password-phone-token-000'}, format='json')
        self.assertIn(gone.status_code, (status.HTTP_200_OK, status.HTTP_204_NO_CONTENT))

    def test_changing_the_password_unlocks_the_app_and_signs_out_other_sessions(self):
        first = self.sign_in().data
        client = self.bearer(first['access'])

        res = client.post('/api/v1/auth/change-password/', {
            'current_password': self.temporary, 'new_password': 'Mango-Tree-2026',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertFalse(res.data['user']['must_change_password'])

        fresh = self.bearer(res.data['access'])
        self.assertEqual(fresh.get('/api/v1/parent/today/').status_code, status.HTTP_200_OK)

        # The session that used the temporary password cannot refresh any more.
        old_refresh = APIClient().post('/api/v1/auth/token/refresh/', {'refresh': first['refresh']}, format='json')
        self.assertEqual(old_refresh.status_code, status.HTTP_401_UNAUTHORIZED)

        self.assertEqual(self.sign_in().status_code, status.HTTP_401_UNAUTHORIZED, 'temporary password is dead')
        new_sign_in = self.sign_in('Mango-Tree-2026')
        self.assertEqual(new_sign_in.status_code, status.HTTP_200_OK)
        self.assertFalse(new_sign_in.data['must_change_password'])

        user = User.objects.get(pk=self.person_id)
        self.assertIsNone(user.temporary_password_expires_at)

    def test_new_password_rules(self):
        client = self.bearer(self.sign_in().data['access'])
        cases = [
            ({'current_password': 'wrong', 'new_password': 'Mango-Tree-2026'}, 'current_password'),
            ({'current_password': self.temporary, 'new_password': self.temporary}, 'new_password'),
            ({'current_password': self.temporary, 'new_password': 'short'}, 'new_password'),
            ({'current_password': self.temporary, 'new_password': '12345678901'}, 'new_password'),
            ({'current_password': self.temporary, 'new_password': 'password123'}, 'new_password'),
        ]
        for payload, field in cases:
            res = client.post('/api/v1/auth/change-password/', payload, format='json')
            self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, payload)
            self.assertIn(field, res.data, payload)
        self.assertTrue(User.objects.get(pk=self.person_id).must_change_password)

    def test_expired_temporary_password_is_refused_at_sign_in(self):
        User.objects.filter(pk=self.person_id).update(temporary_password_expires_at=timezone.now() - timedelta(minutes=1))
        res = self.sign_in()
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertIn('expired', str(res.data))
        legacy = APIClient().post('/api/v1/auth/login/', {'username': User.objects.get(pk=self.person_id).username,
                                                          'password': self.temporary}, format='json')
        self.assertEqual(legacy.status_code, status.HTTP_400_BAD_REQUEST)

    def test_admin_reset_issues_a_new_temporary_password_and_signs_out_devices(self):
        session = self.sign_in().data
        res = self.admin_client.post(f'/api/v1/auth/staff/{self.person_id}/reset-password/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['delivery'], 'shown_to_admin')

        refresh = APIClient().post('/api/v1/auth/token/refresh/', {'refresh': session['refresh']}, format='json')
        self.assertEqual(refresh.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(self.sign_in().status_code, status.HTTP_401_UNAUTHORIZED)
        new = self.sign_in(res.data['temporary_password'])
        self.assertEqual(new.status_code, status.HTTP_200_OK)
        self.assertTrue(new.data['must_change_password'])

    def test_deactivation_ends_every_session(self):
        client = self.bearer(self.sign_in().data['access'])
        session_refresh = self.sign_in().data['refresh']
        client.post('/api/v1/auth/change-password/', {'current_password': self.temporary,
                                                     'new_password': 'Mango-Tree-2026'}, format='json')
        active = self.sign_in('Mango-Tree-2026').data

        self.admin_client.patch(f'/api/v1/auth/staff/{self.person_id}/', {'is_active': False}, format='json')

        self.assertEqual(self.bearer(active['access']).get('/api/v1/auth/me/').status_code, status.HTTP_401_UNAUTHORIZED)
        for refresh in (active['refresh'], session_refresh):
            res = APIClient().post('/api/v1/auth/token/refresh/', {'refresh': refresh}, format='json')
            self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_accounts_that_never_had_a_temporary_password_are_unaffected(self):
        User.objects.create_user(username='legacy_parent', password='Parent@12345', role=User.Role.PARENT,
                                 school=self.school)
        res = APIClient().post('/api/v1/auth/token/', {'username': 'legacy_parent', 'password': 'Parent@12345'},
                               format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertFalse(res.data['must_change_password'])
        self.assertEqual(self.bearer(res.data['access']).get('/api/v1/parent/today/').status_code, status.HTTP_200_OK)
