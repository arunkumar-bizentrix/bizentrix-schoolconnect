"""
Who gets told about what - verified in the backend, through the real APIs.

Families:
  Meena    -> Kavya (5-A)
  Suresh   -> Rahul (5-A)
  Lakshmi  -> Aarav (5-A) and Diya (5-A)     two children, same class
  Ravi     -> Arjun (5-A) and Nila (6-B)     two children, different classes
  Priya     teaches 5-A (class teacher); Vikram teaches 6-B
"""

from datetime import date, timedelta
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from apps.exams.models import Exam, ExamPaper, Mark
from apps.notifications import push
from apps.notifications.models import DeviceToken, Notification
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.timetable.models import Subject

User = get_user_model()


class NotificationTargetingTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name='Aaa Targeting School', code='TGT01')
        self.other_school = School.objects.create(name='Zzz Elsewhere', code='TGT02')

        def user(username, role, school=None, first_name='', active=True):
            return User.objects.create_user(
                username=username, password='x', role=role, first_name=first_name,
                school=school or self.school, is_active=active,
            )

        self.admin = user('tg_admin', User.Role.ADMIN)
        self.priya = user('tg_priya', User.Role.TEACHER, first_name='Priya')
        self.vikram = user('tg_vikram', User.Role.TEACHER, first_name='Vikram')
        self.retired_teacher = user('tg_retired', User.Role.TEACHER, active=False)
        self.meena = user('tg_meena', User.Role.PARENT)
        self.suresh = user('tg_suresh', User.Role.PARENT)
        self.lakshmi = user('tg_lakshmi', User.Role.PARENT)
        self.ravi = user('tg_ravi', User.Role.PARENT)
        self.inactive_parent = user('tg_inactive_parent', User.Role.PARENT, active=False)
        self.outsider = user('tg_outsider', User.Role.PARENT, school=self.other_school)

        self.class_5a = Class.objects.create(school=self.school, name='Grade 5', section='A',
                                             academic_year='2026-2027', class_teacher=self.priya)
        self.class_5a.teachers.add(self.priya)
        self.class_6b = Class.objects.create(school=self.school, name='Grade 6', section='B',
                                             academic_year='2026-2027', class_teacher=self.vikram)
        self.class_6b.teachers.add(self.vikram)

        def child(number, name, classroom, *parents):
            student = Student.objects.create(school=self.school, admission_number=number,
                                             first_name=name, class_enrolled=classroom)
            student.parents.add(*parents)
            return student

        self.kavya = child('T-1', 'Kavya', self.class_5a, self.meena, self.inactive_parent)
        self.rahul = child('T-2', 'Rahul', self.class_5a, self.suresh)
        self.aarav = child('T-3', 'Aarav', self.class_5a, self.lakshmi)
        self.diya = child('T-4', 'Diya', self.class_5a, self.lakshmi)
        self.arjun = child('T-5', 'Arjun', self.class_5a, self.ravi)
        self.nila = child('T-6', 'Nila', self.class_6b, self.ravi)

    # -- helpers ---------------------------------------------------------------------

    def notes(self, user, kind=None):
        rows = Notification.objects.filter(recipient=user)
        return rows.filter(notification_type=kind) if kind else rows

    def mark(self, teacher, classroom, entries, on=None):
        self.client.force_authenticate(user=teacher)
        res = self.client.post('/api/v1/attendance/mark/', {
            'classroom': classroom.id,
            'date': str(on or date.today()),
            'entries': [{'student': s.id, 'status': state} for s, state in entries],
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)

    def homework(self, teacher, classroom):
        self.client.force_authenticate(user=teacher)
        res = self.client.post('/api/v1/homework/', {
            'classroom': classroom.id, 'subject': 'Science', 'title': 'Plant cycle',
            'description': 'Draw it', 'due_date': str(date.today() + timedelta(days=2)),
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        return res.data['id']

    def announce(self, author, **payload):
        self.client.force_authenticate(user=author)
        body = {'title': 'Notice', 'content': 'Please read', 'priority': 'NORMAL'}
        body.update(payload)
        res = self.client.post('/api/v1/announcements/', body, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)

    # -- 1 & 2: attendance ---------------------------------------------------------------

    def test_1_attendance_reaches_only_that_childs_parent(self):
        self.mark(self.priya, self.class_5a, [(self.kavya, 'ABSENT')])

        note = self.notes(self.meena, 'ATTENDANCE').get()
        self.assertEqual(note.student_id, self.kavya.id)
        self.assertIn('Kavya', note.title + note.message)
        self.assertFalse(self.notes(self.suresh).exists())
        self.assertFalse(self.notes(self.inactive_parent).exists(), 'inactive parents get nothing')

    def test_2_student_b_attendance_never_reaches_student_as_parent(self):
        self.mark(self.priya, self.class_5a, [(self.kavya, 'PRESENT')])
        self.mark(self.priya, self.class_5a, [(self.rahul, 'ABSENT')])

        self.assertEqual(self.notes(self.meena, 'ATTENDANCE').count(), 1)
        self.assertEqual(self.notes(self.meena, 'ATTENDANCE').get().student_id, self.kavya.id)
        rahul_note = self.notes(self.suresh, 'ATTENDANCE').get()
        self.assertEqual(rahul_note.student_id, self.rahul.id)
        self.assertFalse(Notification.objects.filter(recipient=self.meena, student=self.rahul).exists())

    def test_unchanged_attendance_does_not_notify_again(self):
        self.mark(self.priya, self.class_5a, [(self.kavya, 'PRESENT')])
        self.mark(self.priya, self.class_5a, [(self.kavya, 'PRESENT')])
        self.assertEqual(self.notes(self.meena, 'ATTENDANCE').count(), 1)

    # -- 3: homework ------------------------------------------------------------------------

    def test_3_class_homework_reaches_every_family_of_that_class_only(self):
        self.homework(self.priya, self.class_5a)

        for parent in (self.meena, self.suresh, self.lakshmi, self.ravi):
            self.assertEqual(self.notes(parent, 'HOMEWORK').count(), 1, parent.username)
        for other in (self.inactive_parent, self.outsider, self.priya, self.vikram, self.admin):
            self.assertFalse(self.notes(other).exists(), other.username)

    def test_homework_for_one_student_reaches_only_that_family(self):
        self.client.force_authenticate(user=self.priya)
        res = self.client.post('/api/v1/homework/', {
            'classroom': self.class_5a.id, 'student': self.kavya.id, 'subject': 'Maths',
            'title': 'Extra practice', 'description': 'd', 'due_date': str(date.today() + timedelta(days=1)),
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.notes(self.meena, 'HOMEWORK').get().student_id, self.kavya.id)
        self.assertFalse(self.notes(self.suresh).exists())

    # -- 4: class announcement ---------------------------------------------------------------

    def test_4_class_announcement_reaches_that_class_families_only(self):
        self.announce(self.priya, audience_type='CLASS', target_class=self.class_5a.id)

        for parent in (self.meena, self.suresh, self.lakshmi, self.ravi):
            self.assertEqual(self.notes(parent, 'ANNOUNCEMENT').count(), 1, parent.username)
        self.assertFalse(self.notes(self.vikram).exists())
        self.assertFalse(self.notes(self.priya).exists(), 'the author is not notified')

    def test_6b_announcement_does_not_reach_5a_only_families(self):
        self.announce(self.vikram, audience_type='CLASS', target_class=self.class_6b.id)
        self.assertEqual(self.notes(self.ravi, 'ANNOUNCEMENT').count(), 1)
        for parent in (self.meena, self.suresh, self.lakshmi):
            self.assertFalse(self.notes(parent).exists(), parent.username)

    # -- 5: school-wide announcement ------------------------------------------------------------

    def test_5_school_wide_notice_reaches_all_parents_and_teachers(self):
        self.announce(self.admin, audience_type='SCHOOL')

        for person in (self.meena, self.suresh, self.lakshmi, self.ravi, self.priya, self.vikram):
            self.assertEqual(self.notes(person, 'ANNOUNCEMENT').count(), 1, person.username)
        for person in (self.admin, self.inactive_parent, self.retired_teacher, self.outsider):
            self.assertFalse(self.notes(person).exists(), person.username)

    # -- 6: results ----------------------------------------------------------------------------

    def _exam_with_marks(self):
        subject = Subject.objects.create(school=self.school, name='Mathematics')
        exam = Exam.objects.create(school=self.school, name='Unit Test 1', academic_year='2026-2027')
        paper_5a = ExamPaper.objects.create(exam=exam, classroom=self.class_5a, subject=subject)
        paper_6b = ExamPaper.objects.create(exam=exam, classroom=self.class_6b, subject=subject)
        for student, score in ((self.kavya, 91), (self.rahul, 64), (self.aarav, 77), (self.diya, 88), (self.arjun, 50)):
            Mark.objects.create(paper=paper_5a, student=student, marks_obtained=score)
        Mark.objects.create(paper=paper_6b, student=self.nila, marks_obtained=70)
        return exam

    def _publish(self, exam):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post(f'/api/v1/exams/{exam.id}/publish/')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)

    def test_6_result_reaches_only_that_childs_parent(self):
        self._publish(self._exam_with_marks())

        kavya_note = self.notes(self.meena, 'RESULT').get()
        self.assertEqual(kavya_note.student_id, self.kavya.id)
        self.assertIn('Kavya scored 91', kavya_note.message)

        rahul_note = self.notes(self.suresh, 'RESULT').get()
        self.assertIn('Rahul', rahul_note.message)
        self.assertNotIn('Kavya', rahul_note.message)
        self.assertFalse(Notification.objects.filter(recipient=self.suresh, student=self.kavya).exists())
        self.assertFalse(self.notes(self.inactive_parent).exists())

    # -- 7: two children, same class ------------------------------------------------------------

    def test_7_two_children_same_class_one_notice_per_class_event(self):
        self.homework(self.priya, self.class_5a)
        self.announce(self.priya, audience_type='CLASS', target_class=self.class_5a.id)

        self.assertEqual(self.notes(self.lakshmi, 'HOMEWORK').count(), 1)
        self.assertEqual(self.notes(self.lakshmi, 'ANNOUNCEMENT').count(), 1)

    def test_7_two_children_same_class_one_notice_per_child_for_child_events(self):
        self.mark(self.priya, self.class_5a, [(self.aarav, 'ABSENT'), (self.diya, 'PRESENT')])
        self._publish(self._exam_with_marks())

        attendance = self.notes(self.lakshmi, 'ATTENDANCE')
        self.assertEqual(sorted(attendance.values_list('student_id', flat=True)), sorted([self.aarav.id, self.diya.id]))
        results = self.notes(self.lakshmi, 'RESULT')
        self.assertEqual(sorted(results.values_list('student_id', flat=True)), sorted([self.aarav.id, self.diya.id]))

    # -- 8: children in different classes -----------------------------------------------------------

    def test_8_children_in_different_classes_hear_about_both(self):
        self.homework(self.priya, self.class_5a)
        self.homework(self.vikram, self.class_6b)
        self.mark(self.priya, self.class_5a, [(self.arjun, 'PRESENT')])
        self.mark(self.vikram, self.class_6b, [(self.nila, 'LATE')])

        self.assertEqual(self.notes(self.ravi, 'HOMEWORK').count(), 2)
        self.assertEqual(
            sorted(self.notes(self.ravi, 'ATTENDANCE').values_list('student_id', flat=True)),
            sorted([self.arjun.id, self.nila.id]),
        )
        # And families of only one of those classes hear about one.
        self.assertEqual(self.notes(self.meena, 'HOMEWORK').count(), 1)

    # -- the API shows each notification's child ---------------------------------------------------------

    def test_notification_api_names_the_child(self):
        self.mark(self.priya, self.class_5a, [(self.aarav, 'ABSENT')])
        self.client.force_authenticate(user=self.lakshmi)
        res = self.client.get('/api/v1/notifications/')
        row = res.data['results'][0]
        self.assertEqual(row['student'], self.aarav.id)
        self.assertEqual(row['student_name'], 'Aarav')


class PushDeliveryRulesTests(NotificationTargetingTests):
    """The phone alerts follow the same rules as the in-app rows."""

    def setUp(self):
        super().setUp()
        for parent in (self.meena, self.suresh, self.lakshmi, self.ravi):
            DeviceToken.objects.create(user=parent, token=f'{parent.username}-phone-token-000000', platform='ANDROID')
        self.sent = []

        def fake_send(tokens, title, body, data=None, validate_only=False):
            self.sent.append({'tokens': tokens, 'title': title, 'body': body, 'data': data})
            return {'sent': len(tokens), 'failed': 0, 'invalid_tokens': [], 'auth_failed': False}

        patcher = mock.patch.object(push, 'send_to_tokens', side_effect=fake_send)
        patcher.start()
        self.addCleanup(patcher.stop)

    def pushes_to(self, parent):
        token = f'{parent.username}-phone-token-000000'
        return [item for item in self.sent if token in item['tokens']]

    def test_parent_of_two_gets_a_phone_alert_for_each_child(self):
        self.mark(self.priya, self.class_5a, [(self.aarav, 'ABSENT'), (self.diya, 'PRESENT')])
        alerts = self.pushes_to(self.lakshmi)
        self.assertEqual(len(alerts), 2)
        self.assertEqual({a['data']['student_id'] for a in alerts}, {self.aarav.id, self.diya.id})

    def test_class_homework_is_one_alert_per_parent(self):
        self.homework(self.priya, self.class_5a)
        self.assertEqual(len(self.pushes_to(self.lakshmi)), 1)
        self.assertEqual(len(self.pushes_to(self.meena)), 1)

    def test_no_alert_leaks_to_another_family(self):
        self.mark(self.priya, self.class_5a, [(self.kavya, 'ABSENT')])
        self.assertEqual(len(self.pushes_to(self.meena)), 1)
        self.assertEqual(self.pushes_to(self.suresh), [])

    @override_settings(PUSH_IN_BACKGROUND=True)
    def test_background_mode_sends_after_commit_not_during_the_request(self):
        started = []

        class InlineThread:
            def __init__(self, target, args, **kwargs):
                self.target, self.args = target, args

            def start(self):
                started.append(True)
                self.target(*self.args)

        with mock.patch('apps.notifications.services.threading.Thread', InlineThread), \
                mock.patch('apps.notifications.services.db_connection.close'):
            with self.captureOnCommitCallbacks(execute=False) as callbacks:
                self.mark(self.priya, self.class_5a, [(self.kavya, 'ABSENT')])
            self.assertEqual(self.sent, [], 'nothing is sent inside the request transaction')
            for callback in callbacks:
                callback()

        self.assertEqual(started, [True])
        self.assertEqual(len(self.pushes_to(self.meena)), 1)
