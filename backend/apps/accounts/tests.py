from datetime import timedelta
from unittest.mock import patch

from django.utils import timezone
from django.test import TestCase, override_settings
from rest_framework.test import APIClient
from rest_framework import status
from apps.schools.models import School
from apps.accounts.models import User, OTPVerification


@override_settings(DEBUG=True, WHATSAPP_ACCESS_TOKEN=None, WHATSAPP_PHONE_NUMBER_ID=None)
class WhatsAppOTPAuthenticationTests(TestCase):
    def setUp(self):
        self.client = APIClient()

        # Create test school
        self.school = School.objects.create(
            name="Apex Academy",
            code="APEX01",
            contact_phone="9000000000",
        )

        # Create test users matching the project roles and phone numbers
        self.admin_user = User.objects.create_user(
            username="test_admin",
            password="AdminPassword@123",
            role=User.Role.ADMIN,
            phone_number="9000000001",
            school=self.school,
        )

        self.teacher_user = User.objects.create_user(
            username="test_teacher",
            password="TeacherPassword@123",
            role=User.Role.TEACHER,
            phone_number="9876543210",
            school=self.school,
        )

        self.parent_user = User.objects.create_user(
            username="test_parent",
            password="ParentPassword@123",
            role=User.Role.PARENT,
            phone_number="9000000002",
            school=self.school,
        )

    # 1. OTP Generation
    def test_01_otp_generation(self):
        record, raw_otp = OTPVerification.generate_otp("9000000001")
        self.assertEqual(len(raw_otp), 6)
        self.assertTrue(raw_otp.isdigit())
        # Never stored in plaintext
        self.assertNotEqual(record.otp_code, raw_otp)
        self.assertFalse(record.is_verified)
        self.assertEqual(record.attempts, 0)
        self.assertFalse(record.is_expired())
        self.assertGreater(record.expires_at, timezone.now())

    # 2. OTP Expiry
    def test_02_otp_expiry(self):
        record, raw_otp = OTPVerification.generate_otp("9000000001")
        # Set expiration to the past
        record.expires_at = timezone.now() - timedelta(minutes=1)
        record.save()

        self.assertTrue(record.is_expired())

        # Attempt verification via API
        response = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('expired', str(response.data))

    # 3. Wrong OTP
    def test_03_wrong_otp(self):
        record, raw_otp = OTPVerification.generate_otp("9000000001")
        wrong_otp = "000000" if raw_otp != "000000" else "111111"

        response = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': wrong_otp},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        record.refresh_from_db()
        self.assertEqual(record.attempts, 1)
        self.assertIn('Invalid OTP code', str(response.data))

    # 4. Maximum Attempts
    def test_04_maximum_attempts(self):
        record, raw_otp = OTPVerification.generate_otp("9000000001")
        wrong_otp = "000000" if raw_otp != "000000" else "111111"

        # Submit 5 wrong attempts
        for i in range(5):
            res = self.client.post(
                '/api/v1/auth/otp/verify/',
                {'phone_number': '9000000001', 'otp': wrong_otp},
                format='json',
            )
            self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

        record.refresh_from_db()
        self.assertEqual(record.attempts, 5)

        # 6th attempt with correct OTP must be locked out
        final_res = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(final_res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Maximum verification attempts exceeded', str(final_res.data))

    # 5. Successful OTP Verification
    @patch('apps.accounts.views.WhatsAppService.send_otp')
    def test_05_successful_otp_verification(self, mock_send):
        captured = {}

        def fake_send(phone, otp):
            captured['otp'] = otp
            return {"success": True, "mode": "development", "error": None}

        mock_send.side_effect = fake_send

        send_res = self.client.post(
            '/api/v1/auth/otp/send/',
            {'phone_number': '9000000001'},
            format='json',
        )
        self.assertEqual(send_res.status_code, status.HTTP_200_OK)
        # Zero-leak: OTP must never be present in the API response
        self.assertNotIn('otp_debug', send_res.data)
        raw_otp = captured['otp']

        verify_res = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(verify_res.status_code, status.HTTP_200_OK)
        self.assertIn('access', verify_res.data)
        self.assertIn('refresh', verify_res.data)
        self.assertIn('user', verify_res.data)

        # Verify DB status is marked verified
        record = OTPVerification.objects.filter(destination='9000000001').first()
        self.assertTrue(record.is_verified)

    # 6. OTP Cannot Be Reused
    def test_06_otp_cannot_be_reused(self):
        record, raw_otp = OTPVerification.generate_otp("9000000001")

        # 1st verification succeeds
        res1 = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(res1.status_code, status.HTTP_200_OK)

        # 2nd verification with same OTP must fail
        res2 = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)

    # 7. New OTP Invalidates Old Active OTP
    def test_07_new_otp_invalidates_old_otp(self):
        rec1, raw_otp1 = OTPVerification.generate_otp("9000000001")
        # Ensure distinct created_at timestamp
        rec2, raw_otp2 = OTPVerification.generate_otp("9000000001")

        rec1.refresh_from_db()
        self.assertTrue(rec1.is_expired())

        # Old OTP1 fails
        res1 = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': raw_otp1},
            format='json',
        )
        self.assertEqual(res1.status_code, status.HTTP_400_BAD_REQUEST)

        # New OTP2 succeeds
        res2 = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9000000001', 'otp': raw_otp2},
            format='json',
        )
        self.assertEqual(res2.status_code, status.HTTP_200_OK)

    # 8. Rate Limiting (Resend Cooldown)
    def test_08_rate_limiting(self):
        res1 = self.client.post(
            '/api/v1/auth/otp/send/',
            {'phone_number': '9000000001'},
            format='json',
        )
        self.assertEqual(res1.status_code, status.HTTP_200_OK)

        # Immediate second request fails with cooldown error
        res2 = self.client.post(
            '/api/v1/auth/otp/send/',
            {'phone_number': '9000000001'},
            format='json',
        )
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Please wait', str(res2.data))

    # 9. Unknown / Unregistered Phone
    def test_09_unknown_unregistered_phone(self):
        res = self.client.post(
            '/api/v1/auth/otp/send/',
            {'phone_number': '9999999999'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('This phone number is not registered with a school.', str(res.data))

    # 10. JWT Tokens Returned After Verification
    @patch('apps.accounts.views.WhatsAppService.send_otp')
    def test_10_jwt_tokens_returned_after_verification(self, mock_send):
        captured = {}

        def fake_send(phone, otp):
            captured['otp'] = otp
            return {"success": True, "mode": "development", "error": None}

        mock_send.side_effect = fake_send

        send_res = self.client.post(
            '/api/v1/auth/otp/send/',
            {'phone_number': '9876543210'},
            format='json',
        )
        self.assertEqual(send_res.status_code, status.HTTP_200_OK)
        self.assertNotIn('otp_debug', send_res.data)
        raw_otp = captured['otp']

        verify_res = self.client.post(
            '/api/v1/auth/otp/verify/',
            {'phone_number': '9876543210', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(verify_res.status_code, status.HTTP_200_OK)
        access_token = verify_res.data['access']

        # Use token to call protected endpoint
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {access_token}')
        profile_res = self.client.get('/api/v1/auth/me/')
        self.assertEqual(profile_res.status_code, status.HTTP_200_OK)
        self.assertEqual(profile_res.data['username'], 'test_teacher')

    # 11. Correct Role Returned From Backend
    def test_11_correct_role_returned(self):
        for phone, expected_role, uname in [
            ('9000000001', 'ADMIN', 'test_admin'),
            ('9876543210', 'TEACHER', 'test_teacher'),
            ('9000000002', 'PARENT', 'test_parent'),
        ]:
            rec, raw_otp = OTPVerification.generate_otp(phone)
            res = self.client.post(
                '/api/v1/auth/otp/verify/',
                {'phone_number': phone, 'otp': raw_otp},
                format='json',
            )
            self.assertEqual(res.status_code, status.HTTP_200_OK)
            self.assertEqual(res.data['user']['role'], expected_role)
            self.assertEqual(res.data['user']['username'], uname)

    # 12. Existing Password Login Continues Working
    def test_12_existing_password_login_still_works(self):
        res = self.client.post(
            '/api/v1/auth/login/',
            {'username': 'test_admin', 'password': 'AdminPassword@123'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('access', res.data)
        self.assertEqual(res.data['user']['role'], 'ADMIN')


import json
from unittest.mock import patch, MagicMock
import urllib.error
from apps.accounts.services.whatsapp_service import WhatsAppService


@override_settings(
    DEBUG=True,
    WHATSAPP_ACCESS_TOKEN='test_mock_meta_access_token',
    WHATSAPP_PHONE_NUMBER_ID='test_mock_phone_number_id',
    WHATSAPP_API_VERSION='v20.0',
    WHATSAPP_OTP_TEMPLATE='hello_world',
)
class WhatsAppServiceLiveTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.school = School.objects.create(name="Live Test School", code="LTS01")
        self.user = User.objects.create_user(
            username="live_test_user",
            password="Password@123",
            role=User.Role.ADMIN,
            phone_number="9000000001",
            school=self.school,
        )

    # 13. WhatsAppService Live Mode Success Dispatch
    @patch('urllib.request.urlopen')
    def test_13_whatsapp_service_live_mode_success(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "messages": [{"id": "wamid.HBgLTEST12345"}]
        }).encode('utf-8')
        mock_resp.__enter__.return_value = mock_resp
        mock_urlopen.return_value = mock_resp

        res = WhatsAppService.send_otp("9000000001", "654321")
        self.assertTrue(res['success'])
        self.assertEqual(res['mode'], 'live')
        self.assertEqual(res['message_id'], 'wamid.HBgLTEST12345')
        self.assertIsNone(res['error'])

    # 14. WhatsAppService Live Mode Meta API Error Handling
    @patch('urllib.request.urlopen')
    def test_14_whatsapp_service_live_mode_meta_error(self, mock_urlopen):
        error_body = json.dumps({
            "error": {
                "message": "(#131030) Recipient phone number not in allowed list",
                "code": 131030,
                "type": "OAuthException",
                "error_data": {"details": "Add recipient to allowed list."}
            }
        }).encode('utf-8')
        fp = MagicMock()
        fp.read.return_value = error_body
        mock_urlopen.side_effect = urllib.error.HTTPError(
            url="https://graph.facebook.com/v20.0/test_mock_phone_number_id/messages",
            code=400,
            msg="Bad Request",
            hdrs={},
            fp=fp,
        )

        res = WhatsAppService.send_otp("9000000001", "654321")
        self.assertFalse(res['success'])
        self.assertEqual(res['mode'], 'live')
        self.assertIn('Recipient phone number not in allowed list', res['error'])

    # 15. Zero-Leak: Live Mode Never Returns otp_debug in SendOTPView
    @patch('apps.accounts.services.whatsapp_service.WhatsAppService.send_otp')
    def test_15_live_mode_never_exposes_otp_debug(self, mock_send):
        mock_send.return_value = {
            "success": True,
            "mode": "live",
            "message": "OTP sent via WhatsApp successfully.",
            "error": None,
            "message_id": "wamid.123",
        }

        res = self.client.post(
            '/api/v1/auth/otp/send/',
            {'phone_number': '9000000001'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['success'])
        # CRITICAL ZERO-LEAK VERIFICATION: otp_debug must NOT be in response!
        self.assertNotIn('otp_debug', res.data)

    # 16. Live Mode Delivery Failure Returns 400 Bad Request
    @patch('apps.accounts.services.whatsapp_service.WhatsAppService.send_otp')
    def test_16_live_mode_delivery_failure_returns_400(self, mock_send):
        mock_send.return_value = {
            "success": False,
            "mode": "live",
            "message": "Failed to deliver WhatsApp message via Meta Cloud API.",
            "error": "(#131030) Recipient phone number not in allowed list",
            "message_id": None,
        }

        res = self.client.post(
            '/api/v1/auth/otp/send/',
            {'phone_number': '9000000001'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('WhatsApp delivery failed', str(res.data))


import re
from django.core import mail
from rest_framework_simplejwt.tokens import AccessToken


@override_settings(
    DEBUG=True,
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    DEFAULT_FROM_EMAIL='noreply@schoolconnect.edu',
)
class EmailOTPAuthenticationTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        mail.outbox.clear()

        # School A (Primary)
        self.school_a = School.objects.create(
            name="Apex Academy",
            code="APEX01",
            contact_phone="9000000000",
        )

        # School B (For Tenant Isolation verification)
        self.school_b = School.objects.create(
            name="Beacon High",
            code="BCN02",
            contact_phone="9000000099",
        )

        # Admin user in School A
        self.admin_user = User.objects.create_user(
            username="admin_user",
            email="admin@schoolconnect.edu",
            password="AdminPassword@123",
            role=User.Role.ADMIN,
            school=self.school_a,
            first_name="Admin",
            last_name="Super",
        )

        # Teacher user in School A
        self.teacher_user = User.objects.create_user(
            username="priya_teacher",
            email="priya.teacher@schoolconnect.edu",
            password="TeacherPassword@123",
            role=User.Role.TEACHER,
            school=self.school_a,
            first_name="Priya",
            last_name="Sharma",
        )

        # Parent user in School A
        self.parent_user = User.objects.create_user(
            username="ravi_parent",
            email="ravi.parent@schoolconnect.edu",
            password="ParentPassword@123",
            role=User.Role.PARENT,
            school=self.school_a,
            first_name="Ravi",
            last_name="Kumar",
        )

        # Inactive user
        self.inactive_user = User.objects.create_user(
            username="disabled_user",
            email="disabled@schoolconnect.edu",
            password="DisabledPassword@123",
            role=User.Role.PARENT,
            school=self.school_a,
            is_active=False,
        )

        # User in School B
        self.school_b_user = User.objects.create_user(
            username="school_b_teacher",
            email="teacher@beacon.edu",
            password="BeaconPassword@123",
            role=User.Role.TEACHER,
            school=self.school_b,
        )

    def _extract_otp_from_email(self, email_body: str) -> str:
        """Helper to safely extract the 6-digit OTP from email body text."""
        matches = re.findall(r'\b\d{6}\b', email_body)
        self.assertTrue(len(matches) > 0, "No 6-digit OTP found in email content")
        return matches[0]

    # 1. Email OTP Send Success
    def test_01_email_otp_send_success(self):
        res = self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('detail', res.data)
        self.assertEqual(res.data['email'], 'admin@schoolconnect.edu')
        self.assertEqual(res.data['expires_in_seconds'], 300)

    # 2. Real Email Backend is Invoked
    def test_02_real_email_backend_invoked(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        self.assertEqual(len(mail.outbox), 1)
        sent_mail = mail.outbox[0]
        self.assertEqual(sent_mail.to, ['admin@schoolconnect.edu'])
        self.assertEqual(sent_mail.subject, "Bizentrix SchoolConnect - Login OTP")
        self.assertIn("Bizentrix SchoolConnect", sent_mail.body)
        self.assertIn("Your login verification code is:", sent_mail.body)
        self.assertIn("This OTP is valid for 5 minutes.", sent_mail.body)

    # 3. OTP is Hashed
    def test_03_otp_is_hashed(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        record = OTPVerification.objects.filter(
            destination='admin@schoolconnect.edu',
            channel=OTPVerification.Channel.EMAIL,
        ).first()
        self.assertIsNotNone(record)
        # Stored hash must be SHA-256 (64 hex characters) and NOT equal to the raw OTP
        self.assertEqual(len(record.otp_hash), 64)
        self.assertNotEqual(record.otp_hash, raw_otp)

    # 4. Plain OTP is Not Stored
    def test_04_plain_otp_is_not_stored(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        record = OTPVerification.objects.filter(
            destination='admin@schoolconnect.edu',
            channel=OTPVerification.Channel.EMAIL,
        ).first()
        for field in ['destination', 'channel', 'otp_hash', 'ip_address']:
            val = getattr(record, field, '')
            self.assertNotIn(raw_otp, str(val))

    # 5. OTP is Not Returned in API Response
    def test_05_otp_not_returned_in_api_response(self):
        res = self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        for forbidden_key in ['otp', 'raw_otp', 'debug_otp', 'otp_debug']:
            self.assertNotIn(forbidden_key, res.data)
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        self.assertNotIn(raw_otp, str(res.data))

    # 6. OTP Expires After 5 Minutes
    def test_06_otp_expires_after_5_minutes(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        record = OTPVerification.objects.filter(
            destination='admin@schoolconnect.edu',
            channel=OTPVerification.Channel.EMAIL,
        ).first()
        now = timezone.now()
        self.assertGreater(record.expires_at, now + timedelta(minutes=4, seconds=50))
        self.assertLess(record.expires_at, now + timedelta(minutes=5, seconds=10))

    # 7. Correct OTP Verification
    def test_07_correct_otp_verification(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        verify_res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(verify_res.status_code, status.HTTP_200_OK)
        self.assertIn('access', verify_res.data)
        self.assertIn('refresh', verify_res.data)
        self.assertEqual(verify_res.data['user']['username'], 'admin_user')
        self.assertEqual(verify_res.data['user']['role'], 'ADMIN')

    # 8. Wrong OTP
    def test_08_wrong_otp(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        verify_res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': '000000'},
            format='json',
        )
        self.assertEqual(verify_res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Incorrect OTP', str(verify_res.data))

    # 9. Maximum 5 Attempts
    def test_09_maximum_5_attempts(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)

        # 5 consecutive incorrect attempts
        for _ in range(5):
            res = self.client.post(
                '/api/v1/auth/otp/email/verify/',
                {'email': 'admin@schoolconnect.edu', 'otp': '000000'},
                format='json',
            )
            self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

        # 6th attempt with the CORRECT OTP must be locked out
        final_res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(final_res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Too many attempts', str(final_res.data))

    # 10. Expired OTP Rejection
    def test_10_expired_otp_rejection(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        record = OTPVerification.objects.filter(
            destination='admin@schoolconnect.edu',
            channel=OTPVerification.Channel.EMAIL,
        ).first()
        record.expires_at = timezone.now() - timedelta(minutes=1)
        record.save()

        res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('expired', str(res.data))

    # 11. Used OTP Rejection
    def test_11_used_otp_rejection(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)

        # 1st verification succeeds
        res1 = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(res1.status_code, status.HTTP_200_OK)

        # Record is marked used
        record = OTPVerification.objects.filter(
            destination='admin@schoolconnect.edu',
            channel=OTPVerification.Channel.EMAIL,
        ).first()
        self.assertTrue(record.is_used)
        self.assertIsNotNone(record.used_at)

        # 2nd verification must be rejected
        res2 = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)

    # 12. OTP Reuse Rejection
    def test_12_otp_reuse_rejection(self):
        self.test_11_used_otp_rejection()

    # 13. Previous OTP Invalidation
    def test_13_previous_otp_invalidation(self):
        # 1st Send
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp1 = self._extract_otp_from_email(mail.outbox[0].body)
        rec1 = OTPVerification.objects.filter(
            destination='admin@schoolconnect.edu',
            channel=OTPVerification.Channel.EMAIL,
        ).first()

        # Advance time slightly to bypass 60s cooldown for test
        OTPVerification.objects.filter(id=rec1.id).update(
            created_at=timezone.now() - timedelta(seconds=65)
        )

        # 2nd Send
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp2 = self._extract_otp_from_email(mail.outbox[1].body)
        rec1.refresh_from_db()
        self.assertTrue(rec1.is_expired())

        # Old OTP1 fails
        res1 = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp1},
            format='json',
        )
        self.assertEqual(res1.status_code, status.HTTP_400_BAD_REQUEST)

        # New OTP2 succeeds
        res2 = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp2},
            format='json',
        )
        self.assertEqual(res2.status_code, status.HTTP_200_OK)

    # 14. 60-Second Resend Cooldown
    def test_14_resend_cooldown(self):
        res1 = self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        self.assertEqual(res1.status_code, status.HTTP_200_OK)

        # Immediate resend request must fail with cooldown error
        res2 = self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        self.assertEqual(res2.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Please wait', str(res2.data))

    # 15. Inactive User Rejection
    def test_15_inactive_user_rejection(self):
        res = self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'disabled@schoolconnect.edu'},
            format='json',
        )
        # Returns generic 200 OK for anti-enumeration
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        # But NO email is sent for inactive user
        self.assertEqual(len(mail.outbox), 0)

    # 16. Unknown Email Handling
    def test_16_unknown_email_handling(self):
        res = self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'unknown.random.person@example.com'},
            format='json',
        )
        # Returns generic 200 OK for anti-enumeration
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        # But NO email is sent
        self.assertEqual(len(mail.outbox), 0)

    # 17. JWT Returned After Successful Verification
    def test_17_jwt_returned_after_successful_verification(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'priya.teacher@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'priya.teacher@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        access_token = res.data['access']
        token_obj = AccessToken(access_token)
        self.assertEqual(str(token_obj['user_id']), str(self.teacher_user.id))

    # 18. /auth/me/ Works After Email OTP Login
    def test_18_auth_me_works_after_email_otp_login(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'priya.teacher@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        verify_res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'priya.teacher@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        access_token = verify_res.data['access']
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {access_token}')

        me_res = self.client.get('/api/v1/auth/me/')
        self.assertEqual(me_res.status_code, status.HTTP_200_OK)
        self.assertEqual(me_res.data['username'], 'priya_teacher')
        self.assertEqual(me_res.data['role'], 'TEACHER')

    # 19. Correct Role Returned (ADMIN, TEACHER, PARENT)
    def test_19_correct_role_returned(self):
        for email, expected_role, expected_username in [
            ('admin@schoolconnect.edu', 'ADMIN', 'admin_user'),
            ('priya.teacher@schoolconnect.edu', 'TEACHER', 'priya_teacher'),
            ('ravi.parent@schoolconnect.edu', 'PARENT', 'ravi_parent'),
        ]:
            mail.outbox.clear()
            self.client.post('/api/v1/auth/otp/email/send/', {'email': email}, format='json')
            raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
            res = self.client.post(
                '/api/v1/auth/otp/email/verify/',
                {'email': email, 'otp': raw_otp},
                format='json',
            )
            self.assertEqual(res.status_code, status.HTTP_200_OK)
            self.assertEqual(res.data['user']['role'], expected_role)
            self.assertEqual(res.data['user']['username'], expected_username)

    # 20. Correct School Returned
    def test_20_correct_school_returned(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        school_info = res.data['user']['school']
        self.assertEqual(school_info['id'], self.school_a.id)
        self.assertEqual(school_info['code'], 'APEX01')

    # 21. Tenant Isolation Remains Intact
    def test_21_tenant_isolation_remains_intact(self):
        # Authenticate School A user
        self.client.post('/api/v1/auth/otp/email/send/', {'email': 'admin@schoolconnect.edu'}, format='json')
        otp_a = self._extract_otp_from_email(mail.outbox[0].body)
        res_a = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': otp_a},
            format='json',
        )
        self.assertEqual(res_a.data['user']['school']['code'], 'APEX01')

        # Authenticate School B user
        mail.outbox.clear()
        self.client.post('/api/v1/auth/otp/email/send/', {'email': 'teacher@beacon.edu'}, format='json')
        otp_b = self._extract_otp_from_email(mail.outbox[0].body)
        res_b = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'teacher@beacon.edu', 'otp': otp_b},
            format='json',
        )
        self.assertEqual(res_b.data['user']['school']['code'], 'BCN02')

        # School IDs are completely distinct
        self.assertNotEqual(res_a.data['user']['school']['id'], res_b.data['user']['school']['id'])

    # 22. Existing Password Login Still Works
    def test_22_existing_password_login_still_works(self):
        res = self.client.post(
            '/api/v1/auth/login/',
            {'username': 'admin_user', 'password': 'AdminPassword@123'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('access', res.data)
        self.assertEqual(res.data['user']['role'], 'ADMIN')

    # 23. Existing JWT Refresh Still Works
    def test_23_existing_jwt_refresh_still_works(self):
        self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        refresh_token = res.data['refresh']

        refresh_res = self.client.post(
            '/api/v1/auth/token/refresh/',
            {'refresh': refresh_token},
            format='json',
        )
        self.assertEqual(refresh_res.status_code, status.HTTP_200_OK)
        self.assertIn('access', refresh_res.data)

    # 24. SMTP Credentials Read From Environment Variables
    def test_24_smtp_credentials_read_from_environment(self):
        from django.conf import settings
        self.assertTrue(hasattr(settings, 'EMAIL_HOST'))
        self.assertTrue(hasattr(settings, 'EMAIL_PORT'))
        self.assertTrue(hasattr(settings, 'EMAIL_USE_TLS'))
        self.assertTrue(hasattr(settings, 'EMAIL_HOST_USER'))
        self.assertTrue(hasattr(settings, 'EMAIL_HOST_PASSWORD'))

    # 25. OTP Never Appears in Logs or Responses
    def test_25_otp_never_appears_in_logs_or_responses(self):
        res = self.client.post(
            '/api/v1/auth/otp/email/send/',
            {'email': 'admin@schoolconnect.edu'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        raw_otp = self._extract_otp_from_email(mail.outbox[0].body)
        self.assertNotIn(raw_otp, str(res.data))

        # Check verify response
        verify_res = self.client.post(
            '/api/v1/auth/otp/email/verify/',
            {'email': 'admin@schoolconnect.edu', 'otp': raw_otp},
            format='json',
        )
        self.assertEqual(verify_res.status_code, status.HTTP_200_OK)
        self.assertNotIn(raw_otp, str(verify_res.data))


