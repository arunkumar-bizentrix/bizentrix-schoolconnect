"""Admin monitoring: dashboard totals, student profile, class overview, teacher profile."""

from datetime import date, timedelta

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.announcements.models import Announcement
from apps.attendance.models import Attendance
from apps.exams.models import Exam, ExamPaper, Mark
from apps.homework.models import Homework
from apps.schools.models import School
from apps.students.models import Class, Student, StudentClassEnrollment
from apps.timetable.models import Subject, TimetableSlot

User = get_user_model()


class MonitoringFixture(APITestCase):
    YEAR = '2026-2027'

    def setUp(self):
        self.today = timezone.localdate()
        self.school = School.objects.create(name='Aaa Monitor School', code='MON01')
        self.other_school = School.objects.create(name='Zzz Monitor Other', code='MON02')

        def user(username, role, school=None, **extra):
            return User.objects.create_user(username=username, password='x', role=role,
                                            school=school or self.school, **extra)

        self.admin = user('mo_admin', User.Role.ADMIN)
        self.priya = user('mo_priya', User.Role.TEACHER, first_name='Priya', last_name='Sharma', phone_number='9000000011')
        self.vikram = user('mo_vikram', User.Role.TEACHER, first_name='Vikram')
        self.idle_teacher = user('mo_idle', User.Role.TEACHER)
        self.parent = user('mo_parent', User.Role.PARENT, first_name='Meena', phone_number='9000000021')
        self.other_parent = user('mo_other_parent', User.Role.PARENT)
        user('mo_elsewhere', User.Role.TEACHER, school=self.other_school)

        self.class_5a = Class.objects.create(school=self.school, name='Grade 5', section='A', academic_year=self.YEAR,
                                             class_teacher=self.priya)
        self.class_5a.teachers.add(self.priya, self.vikram)
        self.class_6b = Class.objects.create(school=self.school, name='Grade 6', section='B', academic_year=self.YEAR)
        self.class_6b.teachers.add(self.vikram)
        Class.objects.create(school=self.school, name='Grade 4', section='A', academic_year='2025-2026')

        self.kavya = Student.objects.create(school=self.school, admission_number='M-1', first_name='Kavya',
                                            class_enrolled=self.class_5a, date_of_birth=date(2016, 5, 2))
        self.kavya.parents.add(self.parent)
        self.rahul = Student.objects.create(school=self.school, admission_number='M-2', first_name='Rahul',
                                            class_enrolled=self.class_5a)
        self.nila = Student.objects.create(school=self.school, admission_number='M-3', first_name='Nila',
                                           class_enrolled=self.class_6b)
        self.nila.parents.add(self.other_parent)
        Student.objects.create(school=self.school, admission_number='M-4', first_name='Unplaced')

        old_class = Class.objects.get(name='Grade 4')
        StudentClassEnrollment.objects.create(school=self.school, student=self.kavya, classroom=old_class,
                                              academic_year='2025-2026', is_current=False)

        maths = Subject.objects.create(school=self.school, name='Mathematics')
        science = Subject.objects.create(school=self.school, name='Science')
        TimetableSlot.objects.create(school=self.school, classroom=self.class_5a, weekday=0, period=1, subject=maths,
                                     teacher=self.priya)
        TimetableSlot.objects.create(school=self.school, classroom=self.class_5a, weekday=1, period=1, subject=maths,
                                     teacher=self.priya)
        TimetableSlot.objects.create(school=self.school, classroom=self.class_5a, weekday=0, period=2, subject=science,
                                     teacher=self.vikram)

        for days_ago, state in [(0, 'PRESENT'), (1, 'ABSENT'), (2, 'LATE'), (3, 'PRESENT')]:
            Attendance.objects.create(school=self.school, student=self.kavya, classroom=self.class_5a,
                                      date=self.today - timedelta(days=days_ago), status=state, marked_by=self.priya)
        Attendance.objects.create(school=self.school, student=self.rahul, classroom=self.class_5a, date=self.today,
                                  status='ABSENT', marked_by=self.priya)

        Homework.objects.create(school=self.school, classroom=self.class_5a, subject='Mathematics', title='Fractions',
                                description='d', assigned_by=self.priya, assigned_date=self.today,
                                due_date=self.today + timedelta(days=2))
        Homework.objects.create(school=self.school, classroom=self.class_5a, subject='Mathematics', title='Only Rahul',
                                description='d', assigned_by=self.priya, student=self.rahul,
                                due_date=self.today + timedelta(days=2))
        Announcement.objects.create(school=self.school, title='Trip', content='c', audience_type='CLASS',
                                    target_class=self.class_5a, created_by=self.priya)

        self.published = Exam.objects.create(school=self.school, name='Unit Test 1', academic_year=self.YEAR,
                                             is_published=True)
        self.draft = Exam.objects.create(school=self.school, name='Quarterly', academic_year=self.YEAR)
        for exam, score in ((self.published, 88), (self.draft, 45)):
            paper = ExamPaper.objects.create(exam=exam, classroom=self.class_5a, subject=maths)
            Mark.objects.create(paper=paper, student=self.kavya, marks_obtained=score, entered_by=self.priya)

    def as_user(self, user):
        self.client.force_authenticate(user=user)


class DashboardSummaryTests(MonitoringFixture):
    def test_real_totals_not_page_lengths(self):
        self.as_user(self.admin)
        res = self.client.get(f'/api/v1/dashboard/summary/?academic_year={self.YEAR}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['counts'], {'students': 4, 'classes': 2, 'teachers': 3, 'parents': 2})
        today = res.data['attendance_today']
        self.assertEqual((today['classes_total'], today['classes_marked'], today['present'], today['absent']), (2, 1, 1, 1))
        self.assertEqual(res.data['exams'], {'published': 1, 'draft': 1})
        self.assertEqual(res.data['homework']['active'], 2)
        self.assertEqual(res.data['needs_attention'], {
            'teachers_without_class': 1, 'classes_without_class_teacher': 1,
            'students_without_class': 1, 'students_without_parent': 2,
        })

    def test_only_admins(self):
        for user in (self.priya, self.parent):
            self.as_user(user)
            self.assertEqual(self.client.get('/api/v1/dashboard/summary/').status_code, status.HTTP_403_FORBIDDEN)

    def test_query_count_does_not_grow_with_the_school(self):
        self.as_user(self.admin)
        with self.assertNumQueries(13):
            self.client.get(f'/api/v1/dashboard/summary/?academic_year={self.YEAR}')
        for i in range(30):
            Student.objects.create(school=self.school, admission_number=f'B-{i}', first_name='Bulk',
                                   class_enrolled=self.class_6b)
        with self.assertNumQueries(13):
            self.client.get(f'/api/v1/dashboard/summary/?academic_year={self.YEAR}')


class StudentProfileTests(MonitoringFixture):
    def test_admin_sees_the_whole_record(self):
        self.as_user(self.admin)
        res = self.client.get(f'/api/v1/students/{self.kavya.id}/profile/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        data = res.data
        self.assertEqual(data['student']['full_name'], 'Kavya')
        self.assertEqual(data['classroom']['class_teacher_name'], 'Priya Sharma')
        self.assertEqual([p['full_name'] for p in data['parents']], ['Meena'])
        self.assertEqual(data['attendance']['days_recorded'], 4)
        self.assertEqual(data['attendance']['percentage'], 75.0)
        self.assertEqual(len(data['attendance']['recent']), 4)
        self.assertEqual([h['title'] for h in data['homework']['recent']], ['Fractions'])
        self.assertEqual({r['exam_name'] for r in data['results']}, {'Unit Test 1', 'Quarterly'})
        unit = next(r for r in data['results'] if r['exam_name'] == 'Unit Test 1')
        self.assertEqual((unit['grade'], unit['rank']), ('A2', 1))
        history = {row['academic_year']: row for row in data['class_history']}
        self.assertEqual(set(history), {'2026-2027', '2025-2026'})
        self.assertEqual(history['2025-2026']['classroom_name'], 'Grade 4 - A')

    def test_one_student_homework_is_not_shown_to_others(self):
        self.as_user(self.admin)
        rahul = self.client.get(f'/api/v1/students/{self.rahul.id}/profile/').data
        self.assertEqual({h['title'] for h in rahul['homework']['recent']}, {'Fractions', 'Only Rahul'})

    def test_parent_sees_own_child_with_published_results_only(self):
        self.as_user(self.parent)
        res = self.client.get(f'/api/v1/students/{self.kavya.id}/profile/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual([r['exam_name'] for r in res.data['results']], ['Unit Test 1'])

    def test_parent_and_teacher_are_blocked_from_others(self):
        self.as_user(self.parent)
        self.assertEqual(self.client.get(f'/api/v1/students/{self.nila.id}/profile/').status_code, status.HTTP_403_FORBIDDEN)
        self.as_user(self.priya)
        self.assertEqual(self.client.get(f'/api/v1/students/{self.nila.id}/profile/').status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.client.get(f'/api/v1/students/{self.kavya.id}/profile/').status_code, status.HTTP_200_OK)


class ClassOverviewTests(MonitoringFixture):
    def test_admin_overview(self):
        self.as_user(self.admin)
        res = self.client.get(f'/api/v1/classes/{self.class_5a.id}/overview/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        data = res.data
        self.assertEqual(data['class_teacher']['full_name'], 'Priya Sharma')
        self.assertEqual({t['full_name']: t['is_class_teacher'] for t in data['teachers']},
                         {'Priya Sharma': True, 'Vikram': False})
        self.assertEqual(data['subjects'], [
            {'subject_name': 'Mathematics', 'teachers': ['Priya Sharma'], 'periods_per_week': 2},
            {'subject_name': 'Science', 'teachers': ['Vikram'], 'periods_per_week': 1},
        ])
        self.assertEqual((data['attendance_today']['present'], data['attendance_today']['absent'],
                          data['attendance_today']['not_marked']), (1, 1, 0))
        rows = {s['full_name']: s for s in data['students']}
        self.assertEqual(rows['Kavya']['attendance_percentage'], 75.0)
        self.assertEqual(rows['Rahul']['attendance_percentage'], 0.0)
        self.assertEqual(rows['Kavya']['parent_count'], 1)
        self.assertEqual({e['name'] for e in data['exams']}, {'Unit Test 1', 'Quarterly'})

    def test_teacher_of_the_class_only(self):
        self.as_user(self.vikram)
        self.assertEqual(self.client.get(f'/api/v1/classes/{self.class_5a.id}/overview/').status_code, status.HTTP_200_OK)
        self.as_user(self.priya)
        self.assertEqual(self.client.get(f'/api/v1/classes/{self.class_6b.id}/overview/').status_code, status.HTTP_404_NOT_FOUND)

    def test_parents_cannot_open_it(self):
        self.as_user(self.parent)
        self.assertIn(self.client.get(f'/api/v1/classes/{self.class_5a.id}/overview/').status_code,
                      (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND))

    def test_student_attendance_is_one_query_not_one_per_student(self):
        self.as_user(self.admin)
        with self.assertNumQueries(8):
            self.client.get(f'/api/v1/classes/{self.class_5a.id}/overview/')
        for i in range(25):
            Student.objects.create(school=self.school, admission_number=f'Q-{i}', first_name='More',
                                   class_enrolled=self.class_5a)
        with self.assertNumQueries(8):
            self.client.get(f'/api/v1/classes/{self.class_5a.id}/overview/')


class TeacherProfileTests(MonitoringFixture):
    def test_admin_sees_classes_subjects_timetable_and_activity(self):
        self.as_user(self.admin)
        res = self.client.get(f'/api/v1/auth/staff/{self.priya.id}/profile/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        data = res.data
        self.assertEqual([(c['name'], c['is_class_teacher']) for c in data['classes']], [('Grade 5 - A', True)])
        self.assertEqual(data['subjects'], [{'subject_name': 'Mathematics', 'classes': ['Grade 5 - A'], 'periods_per_week': 2}])
        periods = [p for day in data['timetable'] for p in day['periods']]
        self.assertEqual(len(periods), 2)
        activity = data['activity_last_30_days']
        self.assertEqual((activity['homework_set'], activity['attendance_days_marked'],
                          activity['announcements_posted'], activity['marks_entered']), (2, 4, 1, 2))

    def test_only_admins_and_only_teachers_of_this_school(self):
        self.as_user(self.priya)
        self.assertEqual(self.client.get(f'/api/v1/auth/staff/{self.vikram.id}/profile/').status_code, status.HTTP_403_FORBIDDEN)
        self.as_user(self.admin)
        elsewhere = User.objects.get(username='mo_elsewhere')
        self.assertEqual(self.client.get(f'/api/v1/auth/staff/{elsewhere.id}/profile/').status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(self.client.get(f'/api/v1/auth/staff/{self.parent.id}/profile/').status_code, status.HTTP_404_NOT_FOUND)
