"""The parent's Today screen."""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.attendance.models import Attendance
from apps.exams.models import Exam, ExamPaper, Mark
from apps.homework.models import Homework
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.timetable.models import Subject, TimetableSlot

User = get_user_model()


class ParentTodayTests(APITestCase):
    def setUp(self):
        self.today = timezone.localdate()
        self.school = School.objects.create(name="Today School", code="TDY01")
        self.teacher = User.objects.create_user(
            username='td_teacher', password='x', role=User.Role.TEACHER, school=self.school,
            first_name='Priya', last_name='Sharma',
        )
        self.parent = User.objects.create_user(
            username='td_parent', password='x', role=User.Role.PARENT, school=self.school,
        )
        self.other_parent = User.objects.create_user(
            username='td_other', password='x', role=User.Role.PARENT, school=self.school,
        )
        self.classroom = Class.objects.create(
            school=self.school, name='Grade 5', section='A', academic_year='2026-2027',
            class_teacher=self.teacher,
        )
        self.classroom.teachers.add(self.teacher)
        self.kavya = Student.objects.create(
            school=self.school, admission_number='T-1', first_name='Kavya',
            class_enrolled=self.classroom,
        )
        self.rahul = Student.objects.create(
            school=self.school, admission_number='T-2', first_name='Rahul',
            class_enrolled=self.classroom,
        )
        self.kavya.parents.add(self.parent)
        self.rahul.parents.add(self.other_parent)
        self.maths = Subject.objects.create(school=self.school, name='Mathematics')

    def get_today(self, user=None, student_id=None):
        self.client.force_authenticate(user=user or self.parent)
        url = '/api/v1/parent/today/'
        if student_id is not None:
            url += f'?student_id={student_id}'
        return self.client.get(url)

    def test_only_their_own_children(self):
        res = self.get_today()
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual([c['student_name'] for c in res.data['children']], ['Kavya'])
        self.assertEqual(res.data['children'][0]['class_teacher_name'], 'Priya Sharma')

    def test_asking_for_someone_elses_child_is_refused(self):
        res = self.get_today(student_id=self.rahul.id)
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_teachers_are_refused(self):
        self.assertEqual(self.get_today(user=self.teacher).status_code, status.HTTP_403_FORBIDDEN)

    def test_attendance_not_marked_yet(self):
        attendance = self.get_today().data['children'][0]['attendance']
        self.assertFalse(attendance['marked'])
        self.assertIsNone(attendance['status'])
        self.assertIsNone(attendance['percentage'])

    def test_attendance_today_and_percentage(self):
        for days_ago, state in [(0, 'PRESENT'), (1, 'ABSENT'), (2, 'LATE'), (3, 'PRESENT')]:
            Attendance.objects.create(
                school=self.school, student=self.kavya, classroom=self.classroom,
                date=self.today - timedelta(days=days_ago), status=state, marked_by=self.teacher,
            )
        attendance = self.get_today().data['children'][0]['attendance']
        self.assertEqual(attendance['status'], 'PRESENT')
        self.assertEqual(attendance['days_recorded'], 4)
        self.assertEqual(attendance['percentage'], 75.0)

    def test_todays_periods_in_order(self):
        weekday = self.today.weekday()
        TimetableSlot.objects.create(
            school=self.school, classroom=self.classroom, weekday=weekday, period=2,
            subject=self.maths, teacher=self.teacher,
        )
        science = Subject.objects.create(school=self.school, name='Science')
        TimetableSlot.objects.create(
            school=self.school, classroom=self.classroom, weekday=weekday, period=1, subject=science,
        )
        TimetableSlot.objects.create(
            school=self.school, classroom=self.classroom, weekday=(weekday + 1) % 7, period=1,
            subject=self.maths,
        )
        periods = self.get_today().data['children'][0]['periods']
        self.assertEqual([p['subject_name'] for p in periods], ['Science', 'Mathematics'])
        self.assertEqual(periods[1]['teacher_name'], 'Priya Sharma')

    def test_homework_given_today_and_due_soon(self):
        def homework(title, assigned, due, student=None, active=True):
            return Homework.objects.create(
                school=self.school, classroom=self.classroom, subject='Mathematics',
                title=title, description='d', assigned_by=self.teacher, student=student,
                assigned_date=assigned, due_date=due, is_active=active,
            )

        homework('Given today', self.today, self.today + timedelta(days=1))
        homework('Due tomorrow', self.today - timedelta(days=2), self.today + timedelta(days=1))
        homework('Due next month', self.today - timedelta(days=2), self.today + timedelta(days=30))
        homework('Overdue', self.today - timedelta(days=5), self.today - timedelta(days=1))
        homework('Only for Rahul', self.today, self.today + timedelta(days=1), student=self.rahul)
        homework('Only for Kavya', self.today, self.today, student=self.kavya)
        homework('Withdrawn', self.today, self.today + timedelta(days=1), active=False)

        child = self.get_today().data['children'][0]
        self.assertEqual(
            sorted(h['title'] for h in child['homework_today']),
            ['Given today', 'Only for Kavya'],
        )
        self.assertEqual([h['title'] for h in child['homework_due_soon']], ['Due tomorrow'])
        kavya_only = next(h for h in child['homework_today'] if h['title'] == 'Only for Kavya')
        self.assertTrue(kavya_only['due_today'])
        self.assertTrue(kavya_only['is_for_this_child_only'])

    def test_latest_result_only_once_published(self):
        exam = Exam.objects.create(school=self.school, name='Unit Test 1', academic_year='2026-2027')
        paper = ExamPaper.objects.create(exam=exam, classroom=self.classroom, subject=self.maths)
        Mark.objects.create(paper=paper, student=self.kavya, marks_obtained=88)
        Mark.objects.create(paper=paper, student=self.rahul, marks_obtained=92)

        self.assertIsNone(self.get_today().data['children'][0]['latest_result'])

        exam.is_published = True
        exam.save()
        result = self.get_today().data['children'][0]['latest_result']
        self.assertEqual(result['exam_name'], 'Unit Test 1')
        self.assertEqual(result['total'], 88.0)
        self.assertEqual(result['rank'], 2)
        self.assertEqual(result['class_size'], 2)
