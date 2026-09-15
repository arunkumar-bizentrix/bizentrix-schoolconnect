"""
The admin's People screen: creating teacher and parent accounts, resetting
passwords, deactivating people who leave - and signing in with a phone number.
"""

from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User
from apps.notifications.models import DeviceToken
from apps.schools.models import School
from apps.students.models import Class, Student


class PeopleManagementTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.school = School.objects.create(name="People School", code="PPL01")
        self.admin = User.objects.create_user(
            username='people_admin', password='Password@123',
            role=User.Role.ADMIN, school=self.school,
        )
        self.teacher = User.objects.create_user(
            username='people_teacher', password='Password@123',
            role=User.Role.TEACHER, school=self.school,
        )
        self.parent = User.objects.create_user(
            username='people_parent', password='Password@123',
            role=User.Role.PARENT, school=self.school,
        )

    def _create(self, **overrides):
        payload = {
            'full_name': 'Priya Sharma',
            'phone_number': '98765 43210',
            'email': 'priya@school.test',
            'role': 'TEACHER',
        }
        payload.update(overrides)
        self.client.force_authenticate(user=self.admin)
        return self.client.post('/api/v1/auth/staff/', payload, format='json')

    def _sign_in(self, identifier, password):
        self.client.force_authenticate(user=None)
        return self.client.post(
            '/api/v1/auth/token/',
            {'username': identifier, 'password': password},
            format='json',
        )

    # ------------------------------------------------------------------
    # creating accounts
    # ------------------------------------------------------------------

    def test_admin_creates_a_teacher_with_a_one_time_password(self):
        res = self._create()

        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['account']['full_name'], 'Priya Sharma')
        self.assertEqual(res.data['account']['phone_number'], '9876543210')
        self.assertEqual(res.data['account']['role'], 'TEACHER')

        password = res.data['temporary_password']
        self.assertRegex(password, r'^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$')

        created = User.objects.get(phone_number='9876543210')
        self.assertEqual(created.school, self.school)
        self.assertNotEqual(created.password, password, 'the password must be hashed')

    def test_new_teacher_signs_in_with_phone_number(self):
        password = self._create().data['temporary_password']
        self.assertEqual(self._sign_in('9876543210', password).status_code, status.HTTP_200_OK)

    def test_phone_sign_in_accepts_country_code_and_spaces(self):
        password = self._create().data['temporary_password']
        self.assertEqual(self._sign_in('+91 98765 43210', password).status_code, status.HTTP_200_OK)

    def test_new_teacher_signs_in_with_email_or_username(self):
        res = self._create()
        password = res.data['temporary_password']
        username = res.data['account']['username']

        self.assertEqual(self._sign_in('PRIYA@school.test', password).status_code, status.HTTP_200_OK)
        self.assertEqual(self._sign_in(username, password).status_code, status.HTTP_200_OK)

    def test_wrong_password_with_phone_is_rejected(self):
        self._create()
        self.assertEqual(
            self._sign_in('9876543210', 'not-the-password').status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    def test_admin_creates_a_parent(self):
        res = self._create(full_name='Ravi Kumar', phone_number='9123456780', email='', role='PARENT')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['account']['role'], 'PARENT')

    def test_two_teachers_cannot_share_a_phone_number(self):
        self._create()
        res = self._create(full_name='Someone Else', email='')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('already exists', res.data['detail'])

    def test_a_parent_may_share_a_phone_with_a_teacher(self):
        """A teacher whose own child studies at the school has both accounts."""
        teacher_password = self._create().data['temporary_password']
        res = self._create(full_name='Priya Sharma', email='', role='PARENT')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

        # The password decides which of the two accounts signs in.
        signed_in = self._sign_in('9876543210', teacher_password)
        self.assertEqual(signed_in.status_code, status.HTTP_200_OK)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {signed_in.data['access']}")
        me = self.client.get('/api/v1/auth/me/')
        self.assertEqual(me.data['role'], 'TEACHER')

    def test_duplicate_email_is_rejected(self):
        self._create()
        res = self._create(full_name='Other', phone_number='9000011111')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_phone_number_must_have_ten_digits(self):
        res = self._create(phone_number='12345')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_admin_accounts_cannot_be_created_here(self):
        res = self._create(role='ADMIN')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(phone_number='9876543210').exists())

    def test_teachers_and_parents_cannot_create_accounts(self):
        for user in (self.teacher, self.parent):
            self.client.force_authenticate(user=user)
            res = self.client.post(
                '/api/v1/auth/staff/',
                {'full_name': 'X Y', 'phone_number': '9876543210', 'role': 'TEACHER'},
                format='json',
            )
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_imported_parent_without_a_password_cannot_be_signed_into(self):
        """Roll-sheet parents have unusable passwords; a phone match alone is not enough."""
        User.objects.create_user(
            username='imported_parent', role=User.Role.PARENT,
            phone_number='9555500000', school=self.school,
        ).set_unusable_password()
        self.assertEqual(self._sign_in('9555500000', '').status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            self._sign_in('9555500000', 'anything').status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    # ------------------------------------------------------------------
    # accounts are provisioned by the school office
    # ------------------------------------------------------------------

    def test_nobody_can_sign_themselves_up_as_a_teacher(self):
        res = self.client.post('/api/v1/auth/register/', {
            'full_name': 'Fake Teacher',
            'password': 'Password@123',
            'phone_number': '9444400000',
            'role': 'TEACHER',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(User.objects.filter(phone_number='9444400000').exists())

    def test_parents_cannot_sign_themselves_up(self):
        res = self.client.post('/api/v1/auth/register/', {
            'full_name': 'New Parent',
            'password': 'Password@123',
            'phone_number': '9444400001',
            'role': 'PARENT',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(User.objects.filter(phone_number='9444400001').exists())

    # ------------------------------------------------------------------
    # after creation
    # ------------------------------------------------------------------

    def test_reset_password_replaces_the_old_one(self):
        res = self._create()
        old_password = res.data['temporary_password']
        person_id = res.data['account']['id']

        self.client.force_authenticate(user=self.admin)
        reset = self.client.post(f'/api/v1/auth/staff/{person_id}/reset-password/')
        self.assertEqual(reset.status_code, status.HTTP_200_OK)
        new_password = reset.data['temporary_password']

        self.assertNotEqual(new_password, old_password)
        self.assertEqual(self._sign_in('9876543210', old_password).status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(self._sign_in('9876543210', new_password).status_code, status.HTTP_200_OK)

    def test_admin_passwords_cannot_be_reset_here(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post(f'/api/v1/auth/staff/{self.admin.id}/reset-password/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_reset_anyone(self):
        self.client.force_authenticate(user=self.teacher)
        res = self.client.post(f'/api/v1/auth/staff/{self.parent.id}/reset-password/')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_deactivated_teacher_cannot_sign_in_and_loses_push(self):
        res = self._create()
        password = res.data['temporary_password']
        person = User.objects.get(pk=res.data['account']['id'])
        DeviceToken.objects.create(user=person, token='phone-token', platform='ANDROID')

        self.client.force_authenticate(user=self.admin)
        patch = self.client.patch(
            f'/api/v1/auth/staff/{person.id}/', {'is_active': False}, format='json'
        )
        self.assertEqual(patch.status_code, status.HTTP_200_OK)
        self.assertFalse(patch.data['is_active'])

        self.assertEqual(self._sign_in('9876543210', password).status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertFalse(DeviceToken.objects.filter(user=person).exists())
        # Deactivated, not deleted: their history stays.
        self.assertTrue(User.objects.filter(pk=person.pk).exists())

    def test_admin_edits_name_and_phone(self):
        person_id = self._create().data['account']['id']
        self.client.force_authenticate(user=self.admin)
        res = self.client.patch(
            f'/api/v1/auth/staff/{person_id}/',
            {'full_name': 'Priya S Raman', 'phone_number': '9000000099'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['full_name'], 'Priya S Raman')
        self.assertEqual(res.data['phone_number'], '9000000099')

    def test_edit_cannot_steal_another_teachers_phone(self):
        self._create()
        other = self._create(full_name='Other Teacher', phone_number='9111122222', email='')
        self.client.force_authenticate(user=self.admin)
        res = self.client.patch(
            f"/api/v1/auth/staff/{other.data['account']['id']}/",
            {'phone_number': '9876543210'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    # ------------------------------------------------------------------
    # listing
    # ------------------------------------------------------------------

    def test_list_shows_a_teachers_classes(self):
        classroom = Class.objects.create(
            school=self.school, name='Grade 5', section='A', academic_year='2026-2027'
        )
        classroom.teachers.add(self.teacher)

        self.client.force_authenticate(user=self.admin)
        res = self.client.get('/api/v1/auth/staff/?role=TEACHER')
        row = next(r for r in res.data if r['id'] == self.teacher.id)
        self.assertEqual(row['linked'], ['Grade 5 - A'])

    def test_list_shows_a_parents_children(self):
        child = Student.objects.create(
            school=self.school, admission_number='P-1', first_name='Kavya', last_name='S'
        )
        child.parents.add(self.parent)

        self.client.force_authenticate(user=self.admin)
        res = self.client.get('/api/v1/auth/staff/?role=PARENT')
        row = next(r for r in res.data if r['id'] == self.parent.id)
        self.assertEqual(row['linked'], ['Kavya S'])

    def test_inactive_people_are_hidden_unless_asked_for(self):
        self.teacher.is_active = False
        self.teacher.save()
        self.client.force_authenticate(user=self.admin)

        default = self.client.get('/api/v1/auth/staff/?role=TEACHER')
        self.assertEqual(default.data, [])

        everyone = self.client.get('/api/v1/auth/staff/?role=TEACHER&include_inactive=1')
        self.assertEqual([r['id'] for r in everyone.data], [self.teacher.id])

    def test_paginated_listing_for_large_parent_lists(self):
        for index in range(35):
            User.objects.create_user(
                username=f'bulk_parent_{index}', role=User.Role.PARENT, school=self.school,
            )
        self.client.force_authenticate(user=self.admin)
        res = self.client.get('/api/v1/auth/staff/?role=PARENT&page=1')

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['count'], 36)
        self.assertEqual(len(res.data['results']), 30)
        self.assertIsNotNone(res.data['next'])

    def test_listing_does_not_query_per_row(self):
        for index in range(20):
            teacher = User.objects.create_user(
                username=f'bulk_teacher_{index}', role=User.Role.TEACHER, school=self.school,
            )
            classroom = Class.objects.create(
                school=self.school, name=f'Grade {index}', section='A',
                academic_year='2026-2027',
            )
            classroom.teachers.add(teacher)

        self.client.force_authenticate(user=self.admin)
        with self.assertNumQueries(2):
            self.client.get('/api/v1/auth/staff/?role=TEACHER')
