"""
IDOR and privilege regression tests across every API.

A malicious client can change any id in a URL, query string or body. These
tests change them and expect the backend - not the app - to refuse. Each
attacker is a real signed-in user of the school, which is the realistic
threat: a parent or teacher poking at ids, not an anonymous stranger.
"""

from datetime import date, timedelta

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.test import APITestCase

from apps.announcements.models import Announcement
from apps.attendance.models import Attendance
from apps.exams.models import Exam, ExamPaper, Mark
from apps.homework.models import Homework
from apps.notifications.models import Notification
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.timetable.models import Subject, TimetableSlot

User = get_user_model()

DENIED = (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND)


class SecurityFixture(APITestCase):
    """Two classes, two teachers, two families - and a second school."""

    def setUp(self):
        self.school = School.objects.create(name='Aaa Secure School', code='SEC01')
        self.other_school = School.objects.create(name='Zzz Other School', code='SEC02')
        today = date.today()

        def user(username, role, school=None, **extra):
            return User.objects.create_user(
                username=username, password='Password@123', role=role,
                school=school or self.school, **extra,
            )

        self.admin = user('sec_admin', User.Role.ADMIN)
        self.teacher_a = user('sec_teacher_a', User.Role.TEACHER, email='teacher.a@secure.test')
        self.teacher_b = user('sec_teacher_b', User.Role.TEACHER)
        self.parent_a = user('sec_parent_a', User.Role.PARENT, phone_number='9811100001')
        self.parent_b = user('sec_parent_b', User.Role.PARENT, phone_number='9811100002',
                             email='parent.b@secure.test')
        self.other_admin = user('sec_other_admin', User.Role.ADMIN, school=self.other_school)
        self.other_parent = user('sec_other_parent', User.Role.PARENT, school=self.other_school,
                                 phone_number='9811100003')

        self.class_a = Class.objects.create(school=self.school, name='Grade 5', section='A',
                                            academic_year='2026-2027', class_teacher=self.teacher_a)
        self.class_a.teachers.add(self.teacher_a)
        self.class_b = Class.objects.create(school=self.school, name='Grade 6', section='B',
                                            academic_year='2026-2027', class_teacher=self.teacher_b)
        self.class_b.teachers.add(self.teacher_b)
        self.other_class = Class.objects.create(school=self.other_school, name='Grade 5', section='A',
                                                academic_year='2026-2027')

        self.child_a = Student.objects.create(school=self.school, admission_number='S-A',
                                              first_name='Kavya', class_enrolled=self.class_a)
        self.child_a.parents.add(self.parent_a)
        self.child_b = Student.objects.create(school=self.school, admission_number='S-B',
                                              first_name='Rahul', class_enrolled=self.class_b)
        self.child_b.parents.add(self.parent_b)
        self.other_child = Student.objects.create(school=self.other_school, admission_number='S-O',
                                                  first_name='Other', class_enrolled=self.other_class)
        self.other_child.parents.add(self.other_parent)

        self.subject = Subject.objects.create(school=self.school, name='Mathematics')
        self.slot_a = TimetableSlot.objects.create(school=self.school, classroom=self.class_a, weekday=0,
                                                   period=1, subject=self.subject, teacher=self.teacher_a)
        self.slot_b = TimetableSlot.objects.create(school=self.school, classroom=self.class_b, weekday=0,
                                                   period=1, subject=self.subject, teacher=self.teacher_b)

        self.att_a = Attendance.objects.create(school=self.school, student=self.child_a, classroom=self.class_a,
                                               date=today, status='PRESENT', marked_by=self.teacher_a)
        self.att_b = Attendance.objects.create(school=self.school, student=self.child_b, classroom=self.class_b,
                                               date=today, status='ABSENT', marked_by=self.teacher_b)

        self.hw_a = Homework.objects.create(school=self.school, classroom=self.class_a, subject='Maths',
                                            title='HW A', description='d', assigned_by=self.teacher_a,
                                            due_date=today + timedelta(days=2))
        self.hw_b = Homework.objects.create(
            school=self.school, classroom=self.class_b, subject='Maths', title='HW B', description='d',
            assigned_by=self.teacher_b, due_date=today + timedelta(days=2),
            attachment=SimpleUploadedFile('worksheet-b.pdf', b'%PDF-1.4 class b only', content_type='application/pdf'),
        )
        self.notice_a = Announcement.objects.create(
            school=self.school, title='Notice A', content='c', audience_type='CLASS',
            target_class=self.class_a, created_by=self.teacher_a,
            attachment=SimpleUploadedFile('consent-a.pdf', b'%PDF-1.4 class a', content_type='application/pdf'),
        )
        self.notice_b = Announcement.objects.create(
            school=self.school, title='Notice B', content='c', audience_type='CLASS',
            target_class=self.class_b, created_by=self.teacher_b,
            attachment=SimpleUploadedFile('consent-b.pdf', b'%PDF-1.4 class b', content_type='application/pdf'),
        )

        self.exam = Exam.objects.create(school=self.school, name='Unit Test', academic_year='2026-2027',
                                        is_published=True)
        self.paper_a = ExamPaper.objects.create(exam=self.exam, classroom=self.class_a, subject=self.subject)
        self.paper_b = ExamPaper.objects.create(exam=self.exam, classroom=self.class_b, subject=self.subject)
        Mark.objects.create(paper=self.paper_a, student=self.child_a, marks_obtained=80)
        Mark.objects.create(paper=self.paper_b, student=self.child_b, marks_obtained=70)
        self.other_exam = Exam.objects.create(school=self.other_school, name='Other', academic_year='2026-2027')

        self.note_b = Notification.objects.create(recipient=self.parent_b, notification_type='HOMEWORK',
                                                  title='t', message='m', homework=self.hw_b)

    def as_user(self, user):
        self.client.force_authenticate(user=user)

    def assertDenied(self, response, msg=''):
        self.assertIn(response.status_code, DENIED, f'{msg}: got {response.status_code} {getattr(response, "data", "")}')


class ParentIdorTests(SecurityFixture):
    """Parent A changes ids to reach Parent B's child."""

    def setUp(self):
        super().setUp()
        self.as_user(self.parent_a)

    def test_student_detail(self):
        self.assertDenied(self.client.get(f'/api/v1/students/{self.child_b.id}/'), 'student detail')
        self.assertDenied(self.client.get(f'/api/v1/students/{self.child_b.id}/enrollments/'), 'enrollments')

    def test_student_list_filters_cannot_widen_scope(self):
        for query in (f'class_id={self.class_b.id}', f'search=Rahul', f'admission_number=S-B'):
            res = self.client.get(f'/api/v1/students/?{query}')
            ids = [row['id'] for row in res.data.get('results', [])] if res.status_code == 200 else []
            self.assertNotIn(self.child_b.id, ids, query)

    def test_class_detail(self):
        self.assertDenied(self.client.get(f'/api/v1/classes/{self.class_b.id}/'))

    def test_attendance_record_and_summary(self):
        self.assertDenied(self.client.get(f'/api/v1/attendance/{self.att_b.id}/'))
        res = self.client.get(f'/api/v1/attendance/?student_id={self.child_b.id}')
        rows = res.data.get('results', res.data) if res.status_code == 200 else []
        self.assertEqual(list(rows), [])
        summary = self.client.get(f'/api/v1/attendance/summary/?student_id={self.child_b.id}')
        if summary.status_code == 200:
            self.assertEqual(summary.data['days_recorded'], 0)
            self.assertEqual(summary.data['recent'], [])
        else:
            self.assertDenied(summary)
        self.assertDenied(self.client.get(f'/api/v1/attendance/sheet/?class_id={self.class_b.id}'))

    def test_homework_and_announcement_detail(self):
        self.assertDenied(self.client.get(f'/api/v1/homework/{self.hw_b.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/announcements/{self.notice_b.id}/'))

    def test_timetable(self):
        self.assertDenied(self.client.get(f'/api/v1/timetable/week/?class_id={self.class_b.id}'))
        self.assertDenied(self.client.get(f'/api/v1/timetable/{self.slot_b.id}/'))

    def test_results_and_report_card(self):
        self.assertDenied(self.client.get(f'/api/v1/report-card/?student_id={self.child_b.id}'))
        self.assertDenied(self.client.get(f'/api/v1/exams/{self.exam.id}/results/?class_id={self.class_b.id}'))
        self.assertDenied(self.client.get(f'/api/v1/exam-papers/{self.paper_b.id}/marks/'))

    def test_parent_today(self):
        self.assertDenied(self.client.get(f'/api/v1/parent/today/?student_id={self.child_b.id}'))

    def test_notifications(self):
        self.assertDenied(self.client.get(f'/api/v1/notifications/{self.note_b.id}/'))
        self.assertDenied(self.client.post(f'/api/v1/notifications/{self.note_b.id}/read/'))
        self.note_b.refresh_from_db()
        self.assertFalse(self.note_b.is_read)

    def test_writes_are_refused(self):
        self.assertDenied(self.client.post('/api/v1/homework/', {
            'classroom': self.class_a.id, 'subject': 'x', 'title': 'x', 'description': 'x',
            'due_date': str(date.today() + timedelta(days=1)),
        }, format='json'), 'homework create')
        self.assertDenied(self.client.post('/api/v1/attendance/mark/', {
            'classroom': self.class_a.id, 'date': str(date.today()),
            'entries': [{'student': self.child_a.id, 'status': 'ABSENT'}],
        }, format='json'), 'attendance mark')
        self.assertDenied(self.client.post(f'/api/v1/students/{self.child_b.id}/link-parent/',
                                           {'parent_id': self.parent_a.id}, format='json'), 'self-link to child')
        self.assertFalse(self.child_b.parents.filter(id=self.parent_a.id).exists())

    def test_attachments_of_another_class(self):
        self.assertDenied(self.client.get(f'/api/v1/announcements/{self.notice_b.id}/attachment/'))
        self.assertDenied(self.client.get(f'/api/v1/homework/{self.hw_b.id}/attachment/'))

    def test_own_attachment_downloads(self):
        res = self.client.get(f'/api/v1/announcements/{self.notice_a.id}/attachment/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(b''.join(res.streaming_content), b'%PDF-1.4 class a')


class TeacherIdorTests(SecurityFixture):
    """Teacher A reaches for Class 6-B, which belongs to Teacher B."""

    def setUp(self):
        super().setUp()
        self.as_user(self.teacher_a)

    def test_reads_of_unrelated_class(self):
        self.assertDenied(self.client.get(f'/api/v1/students/{self.child_b.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/classes/{self.class_b.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/attendance/{self.att_b.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/attendance/sheet/?class_id={self.class_b.id}'))
        self.assertDenied(self.client.get(f'/api/v1/homework/{self.hw_b.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/announcements/{self.notice_b.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/report-card/?student_id={self.child_b.id}'))
        self.assertDenied(self.client.get(f'/api/v1/exams/{self.exam.id}/results/?class_id={self.class_b.id}'))
        self.assertDenied(self.client.get(f'/api/v1/exam-papers/{self.paper_b.id}/marks/'))

    def test_timetable_of_unrelated_class(self):
        self.assertDenied(self.client.get(f'/api/v1/timetable/week/?class_id={self.class_b.id}'))
        self.assertDenied(self.client.get(f'/api/v1/timetable/{self.slot_b.id}/'))
        res = self.client.get(f'/api/v1/timetable/?class_id={self.class_b.id}')
        rows = (res.data if isinstance(res.data, list) else res.data.get('results', [])) if res.status_code == 200 else []
        self.assertEqual(list(rows), [])

    def test_attendance_cannot_be_created_directly_for_another_class(self):
        res = self.client.post('/api/v1/attendance/', {
            'student': self.child_b.id, 'classroom': self.class_b.id,
            'date': str(date.today() - timedelta(days=1)), 'status': 'ABSENT',
        }, format='json')
        self.assertIn(res.status_code, DENIED + (status.HTTP_405_METHOD_NOT_ALLOWED,))
        self.assertFalse(Attendance.objects.filter(student=self.child_b, date=date.today() - timedelta(days=1)).exists())

    def test_own_attendance_record_cannot_be_moved_to_another_student_or_class(self):
        res = self.client.patch(f'/api/v1/attendance/{self.att_a.id}/', {
            'student': self.child_b.id, 'classroom': self.class_b.id,
        }, format='json')
        self.att_a.refresh_from_db()
        self.assertEqual(self.att_a.student_id, self.child_a.id)
        self.assertEqual(self.att_a.classroom_id, self.class_a.id)
        self.assertNotEqual(res.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)

    def test_unrelated_attendance_cannot_be_edited_or_deleted(self):
        self.assertDenied(self.client.patch(f'/api/v1/attendance/{self.att_b.id}/', {'status': 'PRESENT'}, format='json'))
        self.assertDenied(self.client.delete(f'/api/v1/attendance/{self.att_b.id}/'))
        self.att_b.refresh_from_db()
        self.assertEqual(self.att_b.status, 'ABSENT')
        self.assertDenied(self.client.post('/api/v1/attendance/mark/', {
            'classroom': self.class_b.id, 'date': str(date.today()),
            'entries': [{'student': self.child_b.id, 'status': 'PRESENT'}],
        }, format='json'))

    def test_mark_cannot_smuggle_a_student_from_another_class(self):
        res = self.client.post('/api/v1/attendance/mark/', {
            'classroom': self.class_a.id, 'date': str(date.today()),
            'entries': [{'student': self.child_b.id, 'status': 'PRESENT'}],
        }, format='json')
        self.att_b.refresh_from_db()
        self.assertEqual(self.att_b.status, 'ABSENT')
        self.assertFalse(Attendance.objects.filter(student=self.child_b, classroom=self.class_a).exists())
        self.assertNotEqual(res.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)

    def test_homework_cannot_be_moved_to_an_unassigned_class(self):
        res = self.client.patch(f'/api/v1/homework/{self.hw_a.id}/', {'classroom': self.class_b.id}, format='json')
        self.hw_a.refresh_from_db()
        self.assertEqual(self.hw_a.classroom_id, self.class_a.id, f'moved: {res.status_code}')

    def test_unrelated_homework_cannot_be_edited_or_deleted(self):
        self.assertDenied(self.client.patch(f'/api/v1/homework/{self.hw_b.id}/', {'title': 'hacked'}, format='json'))
        self.assertDenied(self.client.delete(f'/api/v1/homework/{self.hw_b.id}/'))
        self.assertTrue(Homework.objects.filter(id=self.hw_b.id, title='HW B').exists())

    def test_class_notice_cannot_become_school_wide(self):
        self.client.patch(f'/api/v1/announcements/{self.notice_a.id}/', {'audience_type': 'SCHOOL', 'target_class': None},
                          format='json')
        self.notice_a.refresh_from_db()
        self.assertEqual(self.notice_a.audience_type, 'CLASS')
        self.assertEqual(self.notice_a.target_class_id, self.class_a.id)

    def test_class_notice_cannot_be_retargeted_to_an_unassigned_class(self):
        self.client.patch(f'/api/v1/announcements/{self.notice_a.id}/', {'target_class': self.class_b.id}, format='json')
        self.notice_a.refresh_from_db()
        self.assertEqual(self.notice_a.target_class_id, self.class_a.id)

    def test_admin_only_writes(self):
        self.assertDenied(self.client.post('/api/v1/classes/', {'name': 'X', 'section': 'Z', 'academic_year': '2026-2027'},
                                           format='json'))
        self.assertDenied(self.client.delete(f'/api/v1/classes/{self.class_a.id}/'))
        self.assertDenied(self.client.post('/api/v1/students/', {
            'first_name': 'X', 'admission_number': 'X-1', 'class_enrolled': self.class_a.id}, format='json'))
        self.assertDenied(self.client.delete(f'/api/v1/students/{self.child_a.id}/'))
        self.assertDenied(self.client.post(f'/api/v1/students/{self.child_a.id}/link-parent/',
                                           {'parent_id': self.parent_b.id}, format='json'))
        self.assertDenied(self.client.patch(f'/api/v1/classes/{self.class_a.id}/', {'teachers': [self.teacher_a.id, self.teacher_b.id]},
                                            format='json'))
        self.assertDenied(self.client.get('/api/v1/auth/staff/?role=PARENT'))
        self.assertDenied(self.client.post(f'/api/v1/auth/staff/{self.parent_b.id}/reset-password/'))
        self.assertDenied(self.client.post('/api/v1/timetable/', {
            'classroom': self.class_a.id, 'weekday': 1, 'period': 2, 'subject': self.subject.id}, format='json'))
        self.assertDenied(self.client.post(f'/api/v1/exams/{self.exam.id}/unpublish/'))

    def test_marks_for_another_class_paper(self):
        self.assertDenied(self.client.post(f'/api/v1/exam-papers/{self.paper_b.id}/marks/', {
            'entries': [{'student': self.child_b.id, 'marks_obtained': 1}]}, format='json'))
        self.assertEqual(float(Mark.objects.get(paper=self.paper_b, student=self.child_b).marks_obtained), 70.0)

    def test_attachments_of_another_class(self):
        self.assertDenied(self.client.get(f'/api/v1/homework/{self.hw_b.id}/attachment/'))
        self.assertDenied(self.client.get(f'/api/v1/announcements/{self.notice_b.id}/attachment/'))


class CrossSchoolTests(SecurityFixture):
    """The deployment serves one school, but the data model keeps a school on
    every row - and the dev database already holds a second school."""

    def test_admin_cannot_reach_another_schools_rows(self):
        self.as_user(self.admin)
        self.assertDenied(self.client.get(f'/api/v1/students/{self.other_child.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/classes/{self.other_class.id}/'))
        self.assertDenied(self.client.get(f'/api/v1/exams/{self.other_exam.id}/'))
        self.assertDenied(self.client.patch(f'/api/v1/auth/staff/{self.other_parent.id}/', {'is_active': False}, format='json'))
        self.assertDenied(self.client.get(f'/api/v1/report-card/?student_id={self.other_child.id}'))

    def test_admin_cannot_link_a_parent_from_another_school(self):
        self.as_user(self.admin)
        res = self.client.post(f'/api/v1/students/{self.child_a.id}/link-parent/',
                               {'parent_id': self.other_parent.id}, format='json')
        self.assertNotEqual(res.status_code, status.HTTP_200_OK)
        self.assertFalse(self.child_a.parents.filter(id=self.other_parent.id).exists())

    def test_partial_phone_number_does_not_link_the_wrong_parent(self):
        self.as_user(self.admin)
        res = self.client.post(f'/api/v1/students/{self.child_a.id}/link-parent/',
                               {'phone_number': '98111'}, format='json')
        self.assertNotEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(list(self.child_a.parents.values_list('id', flat=True)), [self.parent_a.id])

    def test_exact_phone_number_still_links(self):
        self.as_user(self.admin)
        res = self.client.post(f'/api/v1/students/{self.child_a.id}/link-parent/',
                               {'phone_number': '+91 98111 00002'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(self.child_a.parents.filter(id=self.parent_b.id).exists())

    def test_admin_cannot_enrol_into_another_schools_class(self):
        self.as_user(self.admin)
        res = self.client.post(f'/api/v1/students/{self.child_a.id}/enrollments/', {
            'classroom': self.other_class.id, 'academic_year': '2026-2027'}, format='json')
        self.assertNotIn(res.status_code, (status.HTTP_200_OK, status.HTTP_201_CREATED))
        self.child_a.refresh_from_db()
        self.assertEqual(self.child_a.class_enrolled_id, self.class_a.id)

    def test_public_registration_ignores_a_school_id(self):
        res = self.client.post('/api/v1/auth/register/', {
            'full_name': 'New Parent', 'password': 'Password@123', 'phone_number': '9822200001',
            'role': 'PARENT', 'school_id': self.other_school.id,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        created = User.objects.get(phone_number='9822200001')
        self.assertNotEqual(created.school_id, self.other_school.id)


class ProfileTakeoverTests(SecurityFixture):
    """Claiming someone else's email or phone would make OTP sign-in pick the
    wrong account."""

    def test_cannot_take_another_users_email(self):
        self.as_user(self.parent_a)
        res = self.client.patch('/api/v1/auth/me/', {'email': 'TEACHER.A@secure.test'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.parent_a.refresh_from_db()
        self.assertNotEqual(self.parent_a.email.lower(), 'teacher.a@secure.test')

    def test_cannot_take_another_parents_phone(self):
        self.as_user(self.parent_a)
        res = self.client.patch('/api/v1/auth/me/', {'phone_number': '98111 00002'}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cannot_change_own_role_or_school(self):
        self.as_user(self.parent_a)
        self.client.patch('/api/v1/auth/me/', {'role': 'ADMIN', 'school': self.other_school.id, 'is_active': True},
                          format='json')
        self.parent_a.refresh_from_db()
        self.assertEqual(self.parent_a.role, User.Role.PARENT)
        self.assertEqual(self.parent_a.school_id, self.school.id)

    def test_own_details_can_still_change(self):
        self.as_user(self.parent_a)
        res = self.client.patch('/api/v1/auth/me/', {'email': 'new.parent.a@secure.test', 'phone_number': '9811100001'},
                                format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)


class AttachmentExposureTests(SecurityFixture):
    def test_api_never_returns_the_raw_media_path(self):
        self.as_user(self.parent_a)
        res = self.client.get(f'/api/v1/announcements/{self.notice_a.id}/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        body = str(res.data)
        self.assertNotIn('/media/', body)
        self.assertIn(f'/api/v1/announcements/{self.notice_a.id}/attachment/', res.data['attachment_url'])

    def test_unauthenticated_download_is_refused(self):
        self.client.force_authenticate(user=None)
        res = self.client.get(f'/api/v1/announcements/{self.notice_a.id}/attachment/')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_teacher_downloads_own_class_homework_attachment(self):
        self.as_user(self.teacher_b)
        res = self.client.get(f'/api/v1/homework/{self.hw_b.id}/attachment/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(b''.join(res.streaming_content), b'%PDF-1.4 class b only')
