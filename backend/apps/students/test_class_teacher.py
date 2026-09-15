"""The class teacher: one person owns a class's daily attendance."""

from datetime import date

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.schools.models import School
from apps.students.models import Class, Student

User = get_user_model()


class ClassTeacherTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name="Homeroom School", code="HRM01")
        self.admin = User.objects.create_user(
            username='hr_admin', password='x', role=User.Role.ADMIN, school=self.school,
        )
        self.class_teacher = User.objects.create_user(
            username='hr_class_teacher', password='x', role=User.Role.TEACHER,
            school=self.school, first_name='Priya', last_name='Sharma',
        )
        self.subject_teacher = User.objects.create_user(
            username='hr_subject_teacher', password='x', role=User.Role.TEACHER,
            school=self.school,
        )
        self.parent = User.objects.create_user(
            username='hr_parent', password='x', role=User.Role.PARENT, school=self.school,
        )
        self.classroom = Class.objects.create(
            school=self.school, name='Grade 5', section='A', academic_year='2026-2027',
        )
        self.classroom.teachers.add(self.subject_teacher)
        self.student = Student.objects.create(
            school=self.school, admission_number='HR-1', first_name='Kavya',
            class_enrolled=self.classroom,
        )

    def _set_class_teacher(self, teacher_id, **extra):
        self.client.force_authenticate(user=self.admin)
        payload = {'class_teacher': teacher_id}
        payload.update(extra)
        return self.client.patch(f'/api/v1/classes/{self.classroom.id}/', payload, format='json')

    def _mark_as(self, user):
        self.client.force_authenticate(user=user)
        return self.client.post('/api/v1/attendance/mark/', {
            'classroom': self.classroom.id,
            'date': str(date.today()),
            'entries': [{'student': self.student.id, 'status': 'PRESENT'}],
        }, format='json')

    def test_admin_sets_a_class_teacher(self):
        res = self._set_class_teacher(self.class_teacher.id)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['class_teacher'], self.class_teacher.id)
        self.assertEqual(res.data['class_teacher_name'], 'Priya Sharma')

    def test_class_teacher_is_added_to_the_teachers_automatically(self):
        self._set_class_teacher(self.class_teacher.id)
        self.assertTrue(self.classroom.teachers.filter(id=self.class_teacher.id).exists())

    def test_removing_them_from_teachers_clears_class_teacher(self):
        self._set_class_teacher(self.class_teacher.id)

        res = self.client.patch(
            f'/api/v1/classes/{self.classroom.id}/',
            {'teachers': [self.subject_teacher.id]},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIsNone(res.data['class_teacher'])

    def test_a_parent_cannot_be_class_teacher(self):
        res = self._set_class_teacher(self.parent.id)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_teacher_cannot_appoint_a_class_teacher(self):
        self.client.force_authenticate(user=self.subject_teacher)
        res = self.client.patch(
            f'/api/v1/classes/{self.classroom.id}/',
            {'class_teacher': self.subject_teacher.id},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_the_class_teacher_marks_attendance_once_set(self):
        self._set_class_teacher(self.class_teacher.id)

        refused = self._mark_as(self.subject_teacher)
        self.assertEqual(refused.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn('class teacher', str(refused.data))

        self.assertEqual(self._mark_as(self.class_teacher).status_code, status.HTTP_200_OK)

    def test_admin_cannot_mark(self):
        self._set_class_teacher(self.class_teacher.id)
        self.assertEqual(self._mark_as(self.admin).status_code, status.HTTP_403_FORBIDDEN)

    def test_without_a_class_teacher_any_assigned_teacher_still_marks(self):
        """Classes set up before class teachers existed keep working."""
        self.assertEqual(self._mark_as(self.subject_teacher).status_code, status.HTTP_200_OK)

    def test_subject_teacher_can_still_read_the_sheet(self):
        self._set_class_teacher(self.class_teacher.id)
        self.client.force_authenticate(user=self.subject_teacher)
        res = self.client.get(
            f'/api/v1/attendance/sheet/?class_id={self.classroom.id}&date={date.today()}'
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
