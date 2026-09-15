"""Attendance: marking a class, correcting a day, and who may see what."""

from datetime import date, timedelta

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.attendance.models import Attendance
from apps.schools.models import School
from apps.students.models import Class, Student

User = get_user_model()


class AttendanceTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name="Attendance School", code="ATT01")

        self.admin = User.objects.create_user(
            username='att_admin', password='Password@123',
            role=User.Role.ADMIN, school=self.school,
        )
        self.teacher = User.objects.create_user(
            username='att_teacher', password='Password@123',
            role=User.Role.TEACHER, school=self.school,
        )
        self.other_teacher = User.objects.create_user(
            username='att_other_teacher', password='Password@123',
            role=User.Role.TEACHER, school=self.school,
        )
        self.parent = User.objects.create_user(
            username='att_parent', password='Password@123',
            role=User.Role.PARENT, school=self.school,
        )
        self.other_parent = User.objects.create_user(
            username='att_other_parent', password='Password@123',
            role=User.Role.PARENT, school=self.school,
        )

        self.class_a = Class.objects.create(
            school=self.school, name='Grade 5', section='A',
            academic_year='2026-2027',
        )
        self.class_a.teachers.add(self.teacher)
        self.class_b = Class.objects.create(
            school=self.school, name='Grade 6', section='B',
            academic_year='2026-2027',
        )
        self.class_b.teachers.add(self.other_teacher)

        self.kavya = Student.objects.create(
            school=self.school, admission_number='ATT-001',
            first_name='Kavya', last_name='S', class_enrolled=self.class_a,
        )
        self.rahul = Student.objects.create(
            school=self.school, admission_number='ATT-002',
            first_name='Rahul', last_name='M', class_enrolled=self.class_a,
        )
        self.outsider = Student.objects.create(
            school=self.school, admission_number='ATT-003',
            first_name='Ananya', last_name='K', class_enrolled=self.class_b,
        )
        self.kavya.parents.add(self.parent)
        self.outsider.parents.add(self.other_parent)

        self.today = date.today()

    def _mark(self, entries, on_date=None, classroom=None):
        return self.client.post('/api/v1/attendance/mark/', {
            'classroom': (classroom or self.class_a).id,
            'date': str(on_date or self.today),
            'entries': entries,
        }, format='json')

    # ------------------------------------------------------------------
    # marking
    # ------------------------------------------------------------------

    def test_teacher_marks_their_class(self):
        self.client.force_authenticate(user=self.teacher)
        res = self._mark([
            {'student': self.kavya.id, 'status': 'PRESENT'},
            {'student': self.rahul.id, 'status': 'ABSENT', 'note': 'fever'},
        ])

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['created'], 2)
        self.assertEqual(res.data['updated'], 0)

        self.assertEqual(Attendance.objects.count(), 2)
        absent = Attendance.objects.get(student=self.rahul)
        self.assertEqual(absent.status, 'ABSENT')
        self.assertEqual(absent.note, 'fever')
        self.assertEqual(absent.marked_by, self.teacher)

    def test_remarking_the_same_day_corrects_it(self):
        """A child who turns up late must not create a second row."""
        self.client.force_authenticate(user=self.teacher)
        self._mark([{'student': self.kavya.id, 'status': 'ABSENT'}])
        res = self._mark([{'student': self.kavya.id, 'status': 'LATE'}])

        self.assertEqual(res.data['created'], 0)
        self.assertEqual(res.data['updated'], 1)
        self.assertEqual(Attendance.objects.filter(student=self.kavya).count(), 1)
        self.assertEqual(Attendance.objects.get(student=self.kavya).status, 'LATE')

    def test_teacher_cannot_mark_a_class_they_do_not_teach(self):
        self.client.force_authenticate(user=self.teacher)
        res = self._mark(
            [{'student': self.outsider.id, 'status': 'PRESENT'}],
            classroom=self.class_b,
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(Attendance.objects.count(), 0)

    def test_admin_can_mark_any_class(self):
        self.client.force_authenticate(user=self.admin)
        res = self._mark(
            [{'student': self.outsider.id, 'status': 'PRESENT'}],
            classroom=self.class_b,
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    def test_parent_cannot_mark(self):
        self.client.force_authenticate(user=self.parent)
        res = self._mark([{'student': self.kavya.id, 'status': 'PRESENT'}])
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_marking_a_student_from_another_class_is_rejected(self):
        self.client.force_authenticate(user=self.teacher)
        res = self._mark([{'student': self.outsider.id, 'status': 'PRESENT'}])

        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('student_ids', res.data)

    def test_future_dates_are_rejected(self):
        self.client.force_authenticate(user=self.teacher)
        res = self._mark(
            [{'student': self.kavya.id, 'status': 'PRESENT'}],
            on_date=self.today + timedelta(days=1),
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_duplicate_student_in_one_submission_is_rejected(self):
        self.client.force_authenticate(user=self.teacher)
        res = self._mark([
            {'student': self.kavya.id, 'status': 'PRESENT'},
            {'student': self.kavya.id, 'status': 'ABSENT'},
        ])
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_rejected_submission_marks_nobody(self):
        """One bad entry must not leave the register half filled."""
        self.client.force_authenticate(user=self.teacher)
        self._mark([
            {'student': self.kavya.id, 'status': 'PRESENT'},
            {'student': self.outsider.id, 'status': 'PRESENT'},
        ])
        self.assertEqual(Attendance.objects.count(), 0)

    # ------------------------------------------------------------------
    # the register
    # ------------------------------------------------------------------

    def test_sheet_lists_every_student_with_unmarked_status_null(self):
        self.client.force_authenticate(user=self.teacher)
        res = self.client.get(f'/api/v1/attendance/sheet/?class_id={self.class_a.id}')

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['student_count'], 2)
        self.assertFalse(res.data['already_marked'])
        self.assertTrue(all(row['status'] is None for row in res.data['students']))

    def test_sheet_shows_what_was_already_marked(self):
        self.client.force_authenticate(user=self.teacher)
        self._mark([{'student': self.kavya.id, 'status': 'ABSENT', 'note': 'fever'}])

        res = self.client.get(f'/api/v1/attendance/sheet/?class_id={self.class_a.id}')
        self.assertTrue(res.data['already_marked'])
        row = next(r for r in res.data['students'] if r['student'] == self.kavya.id)
        self.assertEqual(row['status'], 'ABSENT')
        self.assertEqual(row['note'], 'fever')

    def test_teacher_cannot_open_another_class_register(self):
        self.client.force_authenticate(user=self.teacher)
        res = self.client.get(f'/api/v1/attendance/sheet/?class_id={self.class_b.id}')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_parent_cannot_open_a_class_register(self):
        self.client.force_authenticate(user=self.parent)
        res = self.client.get(f'/api/v1/attendance/sheet/?class_id={self.class_a.id}')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    # ------------------------------------------------------------------
    # summary
    # ------------------------------------------------------------------

    def test_percentage_counts_late_as_attended(self):
        self.client.force_authenticate(user=self.teacher)
        for offset, mark in enumerate(['PRESENT', 'PRESENT', 'LATE', 'ABSENT']):
            self._mark(
                [{'student': self.kavya.id, 'status': mark}],
                on_date=self.today - timedelta(days=offset),
            )

        self.client.force_authenticate(user=self.parent)
        res = self.client.get(f'/api/v1/attendance/summary/?student_id={self.kavya.id}')

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['days_recorded'], 4)
        self.assertEqual(res.data['present'], 2)
        self.assertEqual(res.data['late'], 1)
        self.assertEqual(res.data['absent'], 1)
        self.assertEqual(res.data['attendance_percentage'], 75.0)

    def test_summary_with_no_records_reports_no_percentage(self):
        self.client.force_authenticate(user=self.parent)
        res = self.client.get(f'/api/v1/attendance/summary/?student_id={self.kavya.id}')

        self.assertEqual(res.data['days_recorded'], 0)
        self.assertIsNone(res.data['attendance_percentage'])

    def test_parent_cannot_see_another_childs_attendance(self):
        self.client.force_authenticate(user=self.teacher)
        self._mark([{'student': self.kavya.id, 'status': 'PRESENT'}])

        self.client.force_authenticate(user=self.other_parent)
        res = self.client.get(f'/api/v1/attendance/summary/?student_id={self.kavya.id}')

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['days_recorded'], 0)

    def test_parent_list_is_scoped_to_their_children(self):
        self.client.force_authenticate(user=self.teacher)
        self._mark([
            {'student': self.kavya.id, 'status': 'PRESENT'},
            {'student': self.rahul.id, 'status': 'PRESENT'},
        ])

        self.client.force_authenticate(user=self.parent)
        res = self.client.get('/api/v1/attendance/')

        rows = res.data.get('results', res.data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['student'], self.kavya.id)

    def test_unauthenticated_is_rejected(self):
        res = self.client.get('/api/v1/attendance/')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)


class AttendanceNotificationTests(APITestCase):
    """
    A parent should learn whether their own child reached school, and should
    not be told about anyone else's child - or told twice about the same day.
    """

    def setUp(self):
        self.school = School.objects.create(name="Notify School", code="NTF01")
        self.teacher = User.objects.create_user(
            username='ntf_teacher', password='Password@123',
            role=User.Role.TEACHER, school=self.school,
        )
        self.classroom = Class.objects.create(
            school=self.school, name='Grade 5', section='A',
            academic_year='2026-2027',
        )
        self.classroom.teachers.add(self.teacher)

        self.kavya = Student.objects.create(
            school=self.school, admission_number='NTF-001',
            first_name='Kavya', last_name='S', class_enrolled=self.classroom,
        )
        self.rahul = Student.objects.create(
            school=self.school, admission_number='NTF-002',
            first_name='Rahul', last_name='M', class_enrolled=self.classroom,
        )

        self.kavya_parent = User.objects.create_user(
            username='ntf_parent_k', password='Password@123',
            role=User.Role.PARENT, school=self.school,
        )
        self.rahul_parent = User.objects.create_user(
            username='ntf_parent_r', password='Password@123',
            role=User.Role.PARENT, school=self.school,
        )
        self.kavya.parents.add(self.kavya_parent)
        self.rahul.parents.add(self.rahul_parent)

        self.today = date.today()
        self.client.force_authenticate(user=self.teacher)

    def _mark(self, entries, on_date=None):
        return self.client.post('/api/v1/attendance/mark/', {
            'classroom': self.classroom.id,
            'date': str(on_date or self.today),
            'entries': entries,
        }, format='json')

    def test_each_parent_hears_about_their_own_child_only(self):
        res = self._mark([
            {'student': self.kavya.id, 'status': 'PRESENT'},
            {'student': self.rahul.id, 'status': 'ABSENT'},
        ])

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['parents_notified'], 2)

        kavya_notifications = self.kavya_parent.notifications.all()
        self.assertEqual(kavya_notifications.count(), 1)
        self.assertIn('Kavya', kavya_notifications.first().title)
        self.assertNotIn('Rahul', kavya_notifications.first().message)

        rahul_notifications = self.rahul_parent.notifications.all()
        self.assertEqual(rahul_notifications.count(), 1)
        self.assertIn('Rahul', rahul_notifications.first().title)

    def test_present_and_absent_read_differently(self):
        self._mark([
            {'student': self.kavya.id, 'status': 'PRESENT'},
            {'student': self.rahul.id, 'status': 'ABSENT'},
        ])

        self.assertIn('in school', self.kavya_parent.notifications.first().title)
        self.assertIn('absent', self.rahul_parent.notifications.first().title.lower())

    def test_the_note_is_passed_on(self):
        self._mark([{'student': self.kavya.id, 'status': 'ABSENT', 'note': 'fever'}])
        self.assertIn('fever', self.kavya_parent.notifications.first().message)

    def test_resaving_an_unchanged_register_sends_nothing(self):
        entries = [{'student': self.kavya.id, 'status': 'PRESENT'}]
        first = self._mark(entries)
        self.assertEqual(first.data['parents_notified'], 1)

        second = self._mark(entries)
        self.assertEqual(second.data['parents_notified'], 0)
        self.assertEqual(self.kavya_parent.notifications.count(), 1)

    def test_correcting_a_mark_sends_one_update(self):
        self._mark([{'student': self.kavya.id, 'status': 'ABSENT'}])
        res = self._mark([{'student': self.kavya.id, 'status': 'LATE'}])

        self.assertEqual(res.data['parents_notified'], 1)
        self.assertEqual(self.kavya_parent.notifications.count(), 2)
        self.assertIn('late', self.kavya_parent.notifications.first().title.lower())

    def test_notification_links_back_to_the_attendance_record(self):
        self._mark([{'student': self.kavya.id, 'status': 'PRESENT'}])

        notification = self.kavya_parent.notifications.first()
        self.assertEqual(notification.notification_type, 'ATTENDANCE')
        self.assertIsNotNone(notification.attendance_id)
        self.assertEqual(notification.attendance.student, self.kavya)

    def test_a_student_with_no_parent_notifies_nobody(self):
        orphan = Student.objects.create(
            school=self.school, admission_number='NTF-003',
            first_name='Solo', last_name='X', class_enrolled=self.classroom,
        )
        res = self._mark([{'student': orphan.id, 'status': 'PRESENT'}])

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['parents_notified'], 0)

    def test_both_parents_of_one_child_are_told(self):
        second_parent = User.objects.create_user(
            username='ntf_parent_k2', password='Password@123',
            role=User.Role.PARENT, school=self.school,
        )
        self.kavya.parents.add(second_parent)

        res = self._mark([{'student': self.kavya.id, 'status': 'PRESENT'}])

        self.assertEqual(res.data['parents_notified'], 2)
        self.assertEqual(second_parent.notifications.count(), 1)

    def test_unread_badge_reflects_attendance(self):
        self._mark([{'student': self.kavya.id, 'status': 'ABSENT'}])

        self.client.force_authenticate(user=self.kavya_parent)
        res = self.client.get('/api/v1/notifications/unread-count/')
        self.assertEqual(res.data['unread_count'], 1)

    def test_parent_can_filter_to_attendance_only(self):
        self._mark([{'student': self.kavya.id, 'status': 'PRESENT'}])

        self.client.force_authenticate(user=self.kavya_parent)
        res = self.client.get('/api/v1/notifications/')
        rows = res.data.get('results', res.data)
        self.assertTrue(all(row['notification_type'] == 'ATTENDANCE' for row in rows))
