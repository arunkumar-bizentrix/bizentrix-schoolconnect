"""Exams: setting papers, entering marks, ranking, publishing, report cards."""

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.exams.models import Exam, ExamPaper, Mark
from apps.exams.services import compute_class_results
from apps.notifications.models import Notification
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.timetable.models import Subject, TimetableSlot

User = get_user_model()


class ExamTestBase(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name="Exam School", code="EXM01")

        def user(username, role, **extra):
            return User.objects.create_user(
                username=username, password='x', role=role, school=self.school, **extra
            )

        self.admin = user('ex_admin', User.Role.ADMIN)
        self.maths_teacher = user('ex_maths', User.Role.TEACHER, first_name='Priya')
        self.science_teacher = user('ex_science', User.Role.TEACHER, first_name='Vikram')
        self.class_teacher = user('ex_class_teacher', User.Role.TEACHER)
        self.outside_teacher = user('ex_outside', User.Role.TEACHER)
        self.parent = user('ex_parent', User.Role.PARENT)
        self.other_parent = user('ex_other_parent', User.Role.PARENT)

        self.classroom = Class.objects.create(
            school=self.school, name='Grade 5', section='A', academic_year='2026-2027',
            class_teacher=self.class_teacher,
        )
        self.classroom.teachers.add(self.maths_teacher, self.science_teacher, self.class_teacher)
        self.other_class = Class.objects.create(
            school=self.school, name='Grade 6', section='B', academic_year='2026-2027',
        )
        self.other_class.teachers.add(self.outside_teacher)

        self.maths = Subject.objects.create(school=self.school, name='Mathematics')
        self.science = Subject.objects.create(school=self.school, name='Science')

        TimetableSlot.objects.create(
            school=self.school, classroom=self.classroom, weekday=0, period=1,
            subject=self.maths, teacher=self.maths_teacher,
        )
        TimetableSlot.objects.create(
            school=self.school, classroom=self.classroom, weekday=0, period=2,
            subject=self.science, teacher=self.science_teacher,
        )

        def student(number, first):
            return Student.objects.create(
                school=self.school, admission_number=number, first_name=first,
                class_enrolled=self.classroom,
            )

        self.kavya = student('E-1', 'Kavya')
        self.rahul = student('E-2', 'Rahul')
        self.aarav = student('E-3', 'Aarav')
        self.meena = student('E-4', 'Meena')
        self.kavya.parents.add(self.parent)
        self.outsider = Student.objects.create(
            school=self.school, admission_number='E-9', first_name='Ananya',
            class_enrolled=self.other_class,
        )
        self.outsider.parents.add(self.other_parent)

    def as_user(self, user):
        self.client.force_authenticate(user=user)

    def create_exam(self, **overrides):
        payload = {
            'name': 'Quarterly Exam',
            'academic_year': '2026-2027',
            'start_date': '2026-09-20',
            'end_date': '2026-09-26',
            'classroom_ids': [self.classroom.id],
            'subject_ids': [self.maths.id, self.science.id],
            'max_marks': 100,
            'pass_marks': 35,
        }
        payload.update(overrides)
        self.as_user(self.admin)
        return self.client.post('/api/v1/exams/', payload, format='json')

    def paper(self, exam_id, subject):
        return ExamPaper.objects.get(exam_id=exam_id, classroom=self.classroom, subject=subject)

    def enter(self, user, paper, entries):
        self.as_user(user)
        return self.client.post(
            f'/api/v1/exam-papers/{paper.id}/marks/', {'entries': entries}, format='json'
        )

    def enter_all(self, exam_id, maths_marks, science_marks):
        maths = self.paper(exam_id, self.maths)
        science = self.paper(exam_id, self.science)
        students = [self.kavya, self.rahul, self.aarav, self.meena]
        self.enter(self.maths_teacher, maths, [
            {'student': s.id, 'marks_obtained': m} for s, m in zip(students, maths_marks)
        ])
        self.enter(self.science_teacher, science, [
            {'student': s.id, 'marks_obtained': m} for s, m in zip(students, science_marks)
        ])


class ExamSetupTests(ExamTestBase):
    def test_admin_creates_exam_with_a_paper_per_class_and_subject(self):
        res = self.create_exam()
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['paper_count'], 2)
        self.assertEqual(res.data['subjects'], ['Mathematics', 'Science'])
        self.assertEqual(res.data['classrooms'], [{'id': self.classroom.id, 'name': 'Grade 5 - A'}])
        self.assertFalse(res.data['is_published'])

    def test_exam_needs_classes_and_subjects(self):
        self.assertEqual(self.create_exam(classroom_ids=[]).status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.create_exam(subject_ids=[]).status_code, status.HTTP_400_BAD_REQUEST)

    def test_pass_marks_cannot_exceed_max(self):
        res = self.create_exam(max_marks=50, pass_marks=60)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_end_date_cannot_precede_start(self):
        res = self.create_exam(start_date='2026-09-20', end_date='2026-09-10')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_teacher_creates_a_test_for_their_class_and_subject(self):
        self.as_user(self.maths_teacher)
        res = self.client.post('/api/v1/exams/', {
            'name': 'X', 'academic_year': '2026-2027',
            'classroom_ids': [self.classroom.id], 'subject_ids': [self.maths.id],
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Exam.objects.get(pk=res.data['id']).created_by, self.maths_teacher)
        notice = Notification.objects.get(exam_id=res.data['id'], recipient=self.parent)
        self.assertIn('New class test', notice.title)
        self.assertEqual(notice.student, self.kavya)

    def test_teacher_cannot_create_a_test_for_another_class(self):
        self.as_user(self.maths_teacher)
        res = self.client.post('/api/v1/exams/', {
            'name': 'X', 'academic_year': '2026-2027',
            'classroom_ids': [self.other_class.id], 'subject_ids': [self.maths.id],
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_admin_adjusts_a_single_paper(self):
        exam_id = self.create_exam().data['id']
        paper = self.paper(exam_id, self.science)
        res = self.client.patch(
            f'/api/v1/exam-papers/{paper.id}/',
            {'max_marks': 50, 'pass_marks': 18, 'exam_date': '2026-09-22'},
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['max_marks'], 50)

    def test_max_marks_cannot_drop_below_an_entered_mark(self):
        exam_id = self.create_exam().data['id']
        paper = self.paper(exam_id, self.maths)
        self.enter(self.maths_teacher, paper, [{'student': self.kavya.id, 'marks_obtained': 88}])
        self.as_user(self.admin)
        res = self.client.patch(f'/api/v1/exam-papers/{paper.id}/', {'max_marks': 50}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_exam_with_marks_cannot_be_deleted(self):
        exam_id = self.create_exam().data['id']
        self.enter(self.maths_teacher, self.paper(exam_id, self.maths), [
            {'student': self.kavya.id, 'marks_obtained': 50},
        ])
        self.as_user(self.admin)
        self.assertEqual(self.client.delete(f'/api/v1/exams/{exam_id}/').status_code, status.HTTP_400_BAD_REQUEST)

    def test_empty_exam_can_be_deleted(self):
        exam_id = self.create_exam().data['id']
        self.assertEqual(self.client.delete(f'/api/v1/exams/{exam_id}/').status_code, status.HTTP_204_NO_CONTENT)

    def test_add_papers_skips_existing_ones(self):
        exam_id = self.create_exam().data['id']
        tamil = Subject.objects.create(school=self.school, name='Tamil')
        res = self.client.post(f'/api/v1/exams/{exam_id}/add-papers/', {
            'classroom_ids': [self.classroom.id],
            'subject_ids': [self.maths.id, tamil.id],
        }, format='json')
        self.assertEqual(res.data['added'], 1)
        self.assertEqual(ExamPaper.objects.filter(exam_id=exam_id).count(), 3)


class MarkEntryTests(ExamTestBase):
    def setUp(self):
        super().setUp()
        self.exam_id = self.create_exam().data['id']
        self.maths_paper = self.paper(self.exam_id, self.maths)
        self.science_paper = self.paper(self.exam_id, self.science)

    def test_subject_teacher_enters_their_subject(self):
        res = self.enter(self.maths_teacher, self.maths_paper, [
            {'student': self.kavya.id, 'marks_obtained': 92},
            {'student': self.rahul.id, 'is_absent': True},
        ])
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['saved'], 2)
        self.assertTrue(Mark.objects.get(student=self.rahul, paper=self.maths_paper).is_absent)
        notice = Notification.objects.get(
            exam_id=self.exam_id,
            student=self.kavya,
            title='Mathematics marks updated',
        )
        self.assertEqual(notice.recipient, self.parent)
        self.assertEqual(
            notice.message,
            'Kavya scored 92/100 in Mathematics for Quarterly Exam.',
        )

    def test_admin_can_view_but_cannot_enter_marks(self):
        self.as_user(self.admin)
        sheet = self.client.get(f'/api/v1/exam-papers/{self.maths_paper.id}/marks/')
        self.assertEqual(sheet.status_code, status.HTTP_200_OK)
        self.assertFalse(sheet.data['paper']['can_enter_marks'])
        result = self.client.post(
            f'/api/v1/exam-papers/{self.maths_paper.id}/marks/',
            {'entries': [{'student': self.kavya.id, 'marks_obtained': 88}]},
            format='json',
        )
        self.assertEqual(result.status_code, status.HTTP_403_FORBIDDEN)

    def test_teacher_cannot_enter_a_subject_they_do_not_teach(self):
        res = self.enter(self.science_teacher, self.maths_paper, [
            {'student': self.kavya.id, 'marks_obtained': 92},
        ])
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_class_teacher_may_enter_any_subject_of_their_class(self):
        res = self.enter(self.class_teacher, self.maths_paper, [
            {'student': self.kavya.id, 'marks_obtained': 70},
        ])
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    def test_teacher_of_another_class_cannot_even_see_the_paper(self):
        res = self.enter(self.outside_teacher, self.maths_paper, [
            {'student': self.kavya.id, 'marks_obtained': 70},
        ])
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_without_a_timetable_any_class_teacher_can_enter(self):
        TimetableSlot.objects.all().delete()
        res = self.enter(self.science_teacher, self.maths_paper, [
            {'student': self.kavya.id, 'marks_obtained': 70},
        ])
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    def test_marks_above_maximum_are_rejected(self):
        res = self.enter(self.maths_teacher, self.maths_paper, [
            {'student': self.kavya.id, 'marks_obtained': 101},
        ])
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(Mark.objects.exists())

    def test_negative_marks_are_rejected(self):
        res = self.enter(self.maths_teacher, self.maths_paper, [
            {'student': self.kavya.id, 'marks_obtained': -1},
        ])
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_student_from_another_class_is_rejected(self):
        res = self.enter(self.maths_teacher, self.maths_paper, [
            {'student': self.outsider.id, 'marks_obtained': 50},
        ])
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_re_entering_updates_instead_of_duplicating(self):
        self.enter(self.maths_teacher, self.maths_paper, [{'student': self.kavya.id, 'marks_obtained': 60}])
        self.enter(self.maths_teacher, self.maths_paper, [{'student': self.kavya.id, 'marks_obtained': 65.5}])
        mark = Mark.objects.get(student=self.kavya, paper=self.maths_paper)
        self.assertEqual(float(mark.marks_obtained), 65.5)
        self.assertEqual(Mark.objects.count(), 1)

    def test_clearing_a_box_removes_the_mark(self):
        self.enter(self.maths_teacher, self.maths_paper, [{'student': self.kavya.id, 'marks_obtained': 60}])
        res = self.enter(self.maths_teacher, self.maths_paper, [{'student': self.kavya.id, 'marks_obtained': None}])
        self.assertEqual(res.data['cleared'], 1)
        self.assertFalse(Mark.objects.exists())

    def test_sheet_lists_every_student_with_their_mark(self):
        self.enter(self.maths_teacher, self.maths_paper, [{'student': self.kavya.id, 'marks_obtained': 60}])
        self.as_user(self.maths_teacher)
        res = self.client.get(f'/api/v1/exam-papers/{self.maths_paper.id}/marks/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        rows = {row['student_name']: row for row in res.data['students']}
        self.assertEqual(set(rows), {'Kavya', 'Rahul', 'Aarav', 'Meena'})
        self.assertEqual(rows['Kavya']['marks_obtained'], 60.0)
        self.assertIsNone(rows['Rahul']['marks_obtained'])
        self.assertTrue(res.data['paper']['can_enter_marks'])

    def test_papers_list_says_which_ones_the_teacher_can_fill(self):
        self.as_user(self.maths_teacher)
        res = self.client.get(f'/api/v1/exams/{self.exam_id}/papers/')
        can = {row['subject_name']: row['can_enter_marks'] for row in res.data}
        self.assertEqual(can, {'Mathematics': True, 'Science': False})

    def test_parent_cannot_open_the_entry_sheet(self):
        self.as_user(self.parent)
        res = self.client.get(f'/api/v1/exam-papers/{self.maths_paper.id}/marks/')
        self.assertIn(res.status_code, (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND))

    def test_published_marks_are_locked(self):
        self.enter_all(self.exam_id, [90, 80, 70, 60], [90, 80, 70, 60])
        self.as_user(self.admin)
        self.client.post(f'/api/v1/exams/{self.exam_id}/publish/')

        res = self.enter(self.maths_teacher, self.maths_paper, [{'student': self.kavya.id, 'marks_obtained': 10}])
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('unpublish', str(res.data))


class RankingTests(ExamTestBase):
    def setUp(self):
        super().setUp()
        self.exam = Exam.objects.get(pk=self.create_exam().data['id'])

    def test_totals_percentages_and_ranks(self):
        # Kavya 180, Rahul 150, Aarav 150, Meena 60
        self.enter_all(self.exam.id, [95, 70, 80, 30], [85, 80, 70, 30])
        results = compute_class_results(self.exam, self.classroom)
        by_name = {row['student_name']: row for row in results['rows']}

        self.assertEqual(by_name['Kavya']['total'], 180.0)
        self.assertEqual(by_name['Kavya']['percentage'], 90.0)
        self.assertEqual(by_name['Kavya']['rank'], 1)
        # A tie shares the rank, and the next rank is skipped.
        self.assertEqual(by_name['Rahul']['rank'], 2)
        self.assertEqual(by_name['Aarav']['rank'], 2)
        self.assertEqual(by_name['Meena']['rank'], 4)
        self.assertEqual(results['rows'][0]['student_name'], 'Kavya')

    def test_below_pass_marks_in_any_subject_fails(self):
        self.enter_all(self.exam.id, [95, 70, 80, 30], [85, 80, 70, 90])
        by_name = {r['student_name']: r for r in compute_class_results(self.exam, self.classroom)['rows']}
        self.assertEqual(by_name['Meena']['result'], 'FAIL')
        self.assertEqual(by_name['Kavya']['result'], 'PASS')

    def test_absent_counts_as_zero_and_fails(self):
        self.enter_all(self.exam.id, [95, 70, 80, 60], [85, 80, 70, 60])
        self.enter(self.science_teacher, self.paper(self.exam.id, self.science), [
            {'student': self.kavya.id, 'is_absent': True},
        ])
        by_name = {r['student_name']: r for r in compute_class_results(self.exam, self.classroom)['rows']}
        self.assertEqual(by_name['Kavya']['total'], 95.0)
        self.assertEqual(by_name['Kavya']['result'], 'FAIL')

    def test_student_with_a_missing_mark_is_not_ranked(self):
        self.enter(self.maths_teacher, self.paper(self.exam.id, self.maths), [
            {'student': self.kavya.id, 'marks_obtained': 99},
            {'student': self.rahul.id, 'marks_obtained': 50},
        ])
        self.enter(self.science_teacher, self.paper(self.exam.id, self.science), [
            {'student': self.rahul.id, 'marks_obtained': 50},
        ])
        results = compute_class_results(self.exam, self.classroom)
        by_name = {r['student_name']: r for r in results['rows']}
        self.assertIsNone(by_name['Kavya']['rank'])
        self.assertEqual(by_name['Kavya']['result'], 'INCOMPLETE')
        self.assertEqual(by_name['Rahul']['rank'], 1)
        self.assertEqual(results['ranked_count'], 1)

    def test_results_endpoint_for_staff(self):
        self.enter_all(self.exam.id, [95, 70, 80, 30], [85, 80, 70, 30])
        self.as_user(self.maths_teacher)
        res = self.client.get(f'/api/v1/exams/{self.exam.id}/results/?class_id={self.classroom.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['max_total'], 200)
        self.assertEqual(res.data['rows'][0]['rank'], 1)

    def test_parent_cannot_see_the_whole_class_results(self):
        self.enter_all(self.exam.id, [95, 70, 80, 30], [85, 80, 70, 30])
        self.as_user(self.admin)
        self.client.post(f'/api/v1/exams/{self.exam.id}/publish/')
        self.as_user(self.parent)
        res = self.client.get(f'/api/v1/exams/{self.exam.id}/results/?class_id={self.classroom.id}')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_results_stay_a_fixed_number_of_queries(self):
        for index in range(40):
            Student.objects.create(
                school=self.school, admission_number=f'BULK-{index}',
                first_name=f'Student{index}', class_enrolled=self.classroom,
            )
        students = list(Student.objects.filter(class_enrolled=self.classroom))
        for paper in ExamPaper.objects.filter(exam=self.exam):
            Mark.objects.bulk_create([
                Mark(paper=paper, student=s, marks_obtained=50) for s in students
            ])
        # papers, marks, students, and the grading scale - never one per student.
        with self.assertNumQueries(4):
            compute_class_results(self.exam, self.classroom)


class PublishingTests(ExamTestBase):
    def setUp(self):
        super().setUp()
        self.exam_id = self.create_exam().data['id']

    def test_publish_refuses_while_marks_are_missing(self):
        self.enter(self.maths_teacher, self.paper(self.exam_id, self.maths), [
            {'student': self.kavya.id, 'marks_obtained': 90},
        ])
        self.as_user(self.admin)
        res = self.client.post(f'/api/v1/exams/{self.exam_id}/publish/')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('7 marks are still not entered', res.data['detail'])
        self.assertFalse(Exam.objects.get(pk=self.exam_id).is_published)

    def test_progress_reports_what_is_missing(self):
        self.as_user(self.admin)
        res = self.client.get(f'/api/v1/exams/{self.exam_id}/progress/')
        self.assertEqual(res.data['missing_total'], 8)

    def test_admin_can_publish_anyway(self):
        self.as_user(self.admin)
        res = self.client.post(f'/api/v1/exams/{self.exam_id}/publish/', {'allow_incomplete': True}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    def test_publishing_notifies_each_parent_with_their_childs_result(self):
        self.enter_all(self.exam_id, [95, 70, 80, 30], [85, 80, 70, 30])
        self.as_user(self.admin)
        res = self.client.post(f'/api/v1/exams/{self.exam_id}/publish/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['parents_notified'], 1)

        note = Notification.objects.get(
            recipient=self.parent,
            title='Quarterly Exam results are out',
        )
        self.assertEqual(note.notification_type, 'RESULT')
        self.assertEqual(note.title, 'Quarterly Exam results are out')
        self.assertEqual(note.message, 'Kavya scored 180/200 (90%) · Grade A2 · Rank 1 of 4.')
        self.assertFalse(Notification.objects.filter(recipient=self.other_parent).exists())

    def test_teacher_cannot_publish(self):
        self.as_user(self.maths_teacher)
        res = self.client.post(f'/api/v1/exams/{self.exam_id}/publish/', {'allow_incomplete': True}, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_unpublish_reopens_marks(self):
        self.enter_all(self.exam_id, [95, 70, 80, 30], [85, 80, 70, 30])
        self.as_user(self.admin)
        self.client.post(f'/api/v1/exams/{self.exam_id}/publish/')
        self.client.post(f'/api/v1/exams/{self.exam_id}/unpublish/')
        res = self.enter(self.maths_teacher, self.paper(self.exam_id, self.maths), [
            {'student': self.kavya.id, 'marks_obtained': 96},
        ])
        self.assertEqual(res.status_code, status.HTTP_200_OK)


class ParentVisibilityTests(ExamTestBase):
    def setUp(self):
        super().setUp()
        self.exam_id = self.create_exam().data['id']
        self.enter_all(self.exam_id, [95, 70, 80, 30], [85, 80, 70, 30])

    def test_parent_sees_nothing_before_publishing(self):
        self.as_user(self.parent)
        exams = self.client.get('/api/v1/exams/')
        rows = exams.data['results'] if isinstance(exams.data, dict) else exams.data
        self.assertEqual(rows, [])

        card = self.client.get(f'/api/v1/report-card/?student_id={self.kavya.id}')
        self.assertEqual(card.status_code, status.HTTP_200_OK)
        self.assertEqual(card.data['exams'], [])

    def test_parent_sees_their_childs_report_card_after_publishing(self):
        self.as_user(self.admin)
        self.client.post(f'/api/v1/exams/{self.exam_id}/publish/')

        self.as_user(self.parent)
        card = self.client.get(f'/api/v1/report-card/?student_id={self.kavya.id}')
        self.assertEqual(card.status_code, status.HTTP_200_OK)
        exam = card.data['exams'][0]
        self.assertEqual(exam['exam_name'], 'Quarterly Exam')
        self.assertEqual(exam['total'], 180.0)
        self.assertEqual(exam['rank'], 1)
        self.assertEqual(exam['class_size'], 4)
        self.assertEqual(exam['result'], 'PASS')
        self.assertEqual(
            [(s['subject'], s['marks_obtained']) for s in exam['subjects']],
            [('Mathematics', 95.0), ('Science', 85.0)],
        )

    def test_parent_cannot_see_another_childs_report_card(self):
        self.as_user(self.admin)
        self.client.post(f'/api/v1/exams/{self.exam_id}/publish/')
        self.as_user(self.parent)
        res = self.client.get(f'/api/v1/report-card/?student_id={self.rahul.id}')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_teacher_sees_unpublished_report_card(self):
        self.as_user(self.maths_teacher)
        res = self.client.get(f'/api/v1/report-card/?student_id={self.kavya.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['exams']), 1)
        self.assertFalse(res.data['exams'][0]['is_published'])

    def test_teacher_of_another_class_cannot_see_report_card(self):
        self.as_user(self.outside_teacher)
        res = self.client.get(f'/api/v1/report-card/?student_id={self.kavya.id}')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_report_card_survives_promotion_to_a_new_class(self):
        self.as_user(self.admin)
        self.client.post(f'/api/v1/exams/{self.exam_id}/publish/')

        next_year = Class.objects.create(
            school=self.school, name='Grade 6', section='A', academic_year='2027-2028',
        )
        self.kavya.class_enrolled = next_year
        self.kavya.save()

        self.as_user(self.parent)
        card = self.client.get(f'/api/v1/report-card/?student_id={self.kavya.id}')
        self.assertEqual(len(card.data['exams']), 1)
        self.assertEqual(card.data['exams'][0]['classroom_name'], 'Grade 5 - A')
        self.assertEqual(card.data['exams'][0]['rank'], 1)
