"""Subjects and the weekly timetable: who may edit it, and who may see what."""

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.schools.models import School
from apps.students.models import Class, Student
from apps.timetable.models import Subject, TimetableSlot

User = get_user_model()

MONDAY = TimetableSlot.Weekday.MONDAY
TUESDAY = TimetableSlot.Weekday.TUESDAY


class TimetableTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name="Timetable School", code="TTB01")

        self.admin = User.objects.create_user(
            username='tt_admin', password='Password@123',
            role=User.Role.ADMIN, school=self.school,
        )
        self.teacher = User.objects.create_user(
            username='tt_teacher', password='Password@123',
            first_name='Priya', last_name='Sharma',
            role=User.Role.TEACHER, school=self.school,
        )
        self.other_teacher = User.objects.create_user(
            username='tt_other', password='Password@123',
            role=User.Role.TEACHER, school=self.school,
        )
        self.parent = User.objects.create_user(
            username='tt_parent', password='Password@123',
            role=User.Role.PARENT, school=self.school,
        )

        self.class_a = Class.objects.create(
            school=self.school, name='Grade 5', section='A',
            academic_year='2026-2027',
        )
        self.class_b = Class.objects.create(
            school=self.school, name='Grade 6', section='B',
            academic_year='2026-2027',
        )

        self.child = Student.objects.create(
            school=self.school, admission_number='TT-001',
            first_name='Kavya', last_name='S', class_enrolled=self.class_a,
        )
        self.child.parents.add(self.parent)

        self.maths = Subject.objects.create(school=self.school, name='Mathematics', code='MATH')
        self.science = Subject.objects.create(school=self.school, name='Science', code='SCI')

    def _slot(self, **overrides):
        payload = {
            'classroom': self.class_a.id,
            'weekday': MONDAY,
            'period': 1,
            'subject': self.maths.id,
            'teacher': self.teacher.id,
            'start_time': '09:00',
            'end_time': '09:45',
        }
        payload.update(overrides)
        return payload

    # ------------------------------------------------------------------
    # subjects
    # ------------------------------------------------------------------

    def test_admin_creates_a_subject(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post('/api/v1/subjects/', {'name': 'Tamil', 'code': 'TAM'}, format='json')

        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertTrue(Subject.objects.filter(school=self.school, name='Tamil').exists())

    def test_duplicate_subject_name_is_rejected_case_insensitively(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post('/api/v1/subjects/', {'name': 'mathematics'}, format='json')

        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('already exists', str(res.data))

    def test_teacher_can_read_but_not_create_subjects(self):
        self.client.force_authenticate(user=self.teacher)
        self.assertEqual(self.client.get('/api/v1/subjects/').status_code, status.HTTP_200_OK)

        res = self.client.post('/api/v1/subjects/', {'name': 'Hindi'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    # ------------------------------------------------------------------
    # building the timetable
    # ------------------------------------------------------------------

    def test_admin_adds_a_period(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post('/api/v1/timetable/', self._slot(), format='json')

        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['subject_name'], 'Mathematics')
        self.assertEqual(res.data['teacher_name'], 'Priya Sharma')
        self.assertEqual(res.data['time_display'], '9:00 AM - 9:45 AM')

    def test_teacher_cannot_edit_the_timetable(self):
        self.client.force_authenticate(user=self.teacher)
        res = self.client.post('/api/v1/timetable/', self._slot(), format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_class_cannot_have_two_subjects_in_one_period(self):
        self.client.force_authenticate(user=self.admin)
        self.client.post('/api/v1/timetable/', self._slot(), format='json')
        res = self.client.post(
            '/api/v1/timetable/',
            self._slot(subject=self.science.id, teacher=self.other_teacher.id),
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_teacher_cannot_be_in_two_classes_at_once(self):
        self.client.force_authenticate(user=self.admin)
        self.client.post('/api/v1/timetable/', self._slot(), format='json')

        res = self.client.post(
            '/api/v1/timetable/',
            self._slot(classroom=self.class_b.id),
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('already teaches', str(res.data))

    def test_the_same_teacher_may_take_a_different_period(self):
        self.client.force_authenticate(user=self.admin)
        self.client.post('/api/v1/timetable/', self._slot(), format='json')
        res = self.client.post(
            '/api/v1/timetable/',
            self._slot(classroom=self.class_b.id, period=2),
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

    def test_end_time_must_follow_start_time(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post(
            '/api/v1/timetable/',
            self._slot(start_time='10:00', end_time='09:30'),
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_parent_cannot_be_assigned_as_the_teacher(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post(
            '/api/v1/timetable/', self._slot(teacher=self.parent.id), format='json'
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    # ------------------------------------------------------------------
    # reading it
    # ------------------------------------------------------------------

    def _build_week(self):
        self.client.force_authenticate(user=self.admin)
        self.client.post('/api/v1/timetable/', self._slot(), format='json')
        self.client.post(
            '/api/v1/timetable/',
            self._slot(period=2, subject=self.science.id),
            format='json',
        )
        self.client.post(
            '/api/v1/timetable/',
            self._slot(weekday=TUESDAY, period=1, subject=self.science.id),
            format='json',
        )

    def test_week_is_grouped_by_day(self):
        self._build_week()
        self.client.force_authenticate(user=self.teacher)

        res = self.client.get(f'/api/v1/timetable/week/?class_id={self.class_a.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        days = {day['weekday']: day for day in res.data['days']}
        self.assertEqual(len(days[MONDAY]['periods']), 2)
        self.assertEqual(len(days[TUESDAY]['periods']), 1)
        self.assertEqual(days[MONDAY]['periods'][0]['period'], 1)

    def test_teacher_sees_their_own_schedule(self):
        self._build_week()
        self.client.force_authenticate(user=self.teacher)

        res = self.client.get('/api/v1/timetable/my/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        periods = [p for day in res.data['days'] for p in day['periods']]
        self.assertEqual(len(periods), 3)
        self.assertTrue(all(p['teacher'] == self.teacher.id for p in periods))

    def test_another_teachers_schedule_is_empty_not_leaked(self):
        self._build_week()
        self.client.force_authenticate(user=self.other_teacher)

        res = self.client.get('/api/v1/timetable/my/')
        periods = [p for day in res.data['days'] for p in day['periods']]
        self.assertEqual(periods, [])

    def test_parent_sees_their_childs_class_week(self):
        self._build_week()
        self.client.force_authenticate(user=self.parent)

        res = self.client.get(f'/api/v1/timetable/week/?class_id={self.class_a.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        periods = [p for day in res.data['days'] for p in day['periods']]
        self.assertEqual(len(periods), 3)

    def test_parent_cannot_see_an_unrelated_class_week(self):
        self._build_week()
        self.client.force_authenticate(user=self.admin)
        self.client.post(
            '/api/v1/timetable/',
            self._slot(classroom=self.class_b.id, period=5, teacher=self.other_teacher.id),
            format='json',
        )

        self.client.force_authenticate(user=self.parent)
        res = self.client.get(f'/api/v1/timetable/week/?class_id={self.class_b.id}')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_parent_list_is_scoped_to_their_childrens_classes(self):
        self._build_week()
        self.client.force_authenticate(user=self.admin)
        self.client.post(
            '/api/v1/timetable/',
            self._slot(classroom=self.class_b.id, period=6, teacher=self.other_teacher.id),
            format='json',
        )

        self.client.force_authenticate(user=self.parent)
        res = self.client.get('/api/v1/timetable/')
        rows = res.data if isinstance(res.data, list) else res.data.get('results', [])
        self.assertTrue(all(row['classroom'] == self.class_a.id for row in rows))

    def test_parents_have_no_personal_schedule(self):
        self.client.force_authenticate(user=self.parent)
        res = self.client.get('/api/v1/timetable/my/')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_week_requires_a_class(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.get('/api/v1/timetable/week/')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_unauthenticated_is_rejected(self):
        self.assertEqual(
            self.client.get('/api/v1/timetable/').status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    def test_admin_can_delete_a_period(self):
        self.client.force_authenticate(user=self.admin)
        created = self.client.post('/api/v1/timetable/', self._slot(), format='json')
        res = self.client.delete(f"/api/v1/timetable/{created.data['id']}/")

        self.assertEqual(res.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(TimetableSlot.objects.count(), 0)

    def test_a_subject_in_use_cannot_be_deleted(self):
        """PROTECT keeps a timetable from losing the subject it points at."""
        self.client.force_authenticate(user=self.admin)
        self.client.post('/api/v1/timetable/', self._slot(), format='json')

        with self.assertRaises(Exception):
            self.maths.delete()
