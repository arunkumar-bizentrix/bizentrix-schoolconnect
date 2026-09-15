"""Grades: thresholds, edge cases, per-subject and overall, scale editing, visibility."""

from decimal import Decimal
from importlib import import_module

from django.apps import apps as global_apps
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.exams.grading import DEFAULT_GRADE_BANDS, grade_for, validate_bands
from apps.exams.models import Exam, ExamPaper, GradeBand, Mark
from apps.exams.services import compute_class_results
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.timetable.models import Subject

User = get_user_model()
BANDS = list(DEFAULT_GRADE_BANDS)


class GradeForTests(APITestCase):
    def test_approved_default_scale(self):
        self.assertEqual(
            [(label, int(minimum)) for label, minimum, _ in BANDS],
            [('A1', 91), ('A2', 81), ('B1', 71), ('B2', 61), ('C1', 51), ('C2', 41), ('D', 33), ('E', 0)],
        )

    def test_every_boundary(self):
        cases = {
            100: 'A1', 91: 'A1', 90.9: 'A2', 81: 'A2', 80.9: 'B1', 71: 'B1', 70.9: 'B2', 61: 'B2',
            60.9: 'C1', 51: 'C1', 50.9: 'C2', 41: 'C2', 40.9: 'D', 33: 'D', 32.9: 'E', 0: 'E',
        }
        for percentage, expected in cases.items():
            self.assertEqual(grade_for(percentage, BANDS), expected, percentage)

    def test_graded_on_the_displayed_percentage(self):
        """90.95 percent is shown as 91.0, so it must not be graded A2."""
        self.assertEqual(grade_for(90.95, BANDS), 'A1')
        self.assertEqual(grade_for(90.94, BANDS), 'A2')
        self.assertEqual(grade_for(32.95, BANDS), 'D')

    def test_nothing_to_grade(self):
        self.assertIsNone(grade_for(None, BANDS))

    def test_scale_with_no_zero_band_leaves_low_scores_ungraded(self):
        self.assertIsNone(grade_for(10, [('P', Decimal('40'), '')]))


class ValidateBandsTests(APITestCase):
    def band(self, label, minimum):
        return {'label': label, 'min_percentage': Decimal(str(minimum))}

    def test_default_scale_is_valid(self):
        self.assertEqual(validate_bands([self.band(label, minimum) for label, minimum, _ in BANDS]), [])

    def test_problems(self):
        self.assertIn('Add at least one grade.', validate_bands([]))
        self.assertTrue(any('0%' in p for p in validate_bands([self.band('A', 50)])))
        self.assertTrue(any('twice' in p for p in validate_bands([self.band('A', 50), self.band('a', 0)])))
        self.assertTrue(any('Two grades start' in p for p in validate_bands([self.band('A', 0), self.band('B', 0)])))
        self.assertTrue(any('between 0 and 100' in p for p in validate_bands([self.band('A', 101), self.band('E', 0)])))
        self.assertTrue(any('label' in p for p in validate_bands([self.band('', 0)])))


class ResultGradeTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name='Grade School', code='GRD01')
        self.admin = User.objects.create_user(username='gr_admin', password='x', role=User.Role.ADMIN, school=self.school)
        self.teacher = User.objects.create_user(username='gr_teacher', password='x', role=User.Role.TEACHER, school=self.school)
        self.parent = User.objects.create_user(username='gr_parent', password='x', role=User.Role.PARENT, school=self.school)
        self.classroom = Class.objects.create(school=self.school, name='Grade 8', section='A',
                                              academic_year='2026-2027', class_teacher=self.teacher)
        self.classroom.teachers.add(self.teacher)
        self.maths = Subject.objects.create(school=self.school, name='Mathematics')
        self.practical = Subject.objects.create(school=self.school, name='Science Practical')
        self.exam = Exam.objects.create(school=self.school, name='Quarterly', academic_year='2026-2027')
        self.maths_paper = ExamPaper.objects.create(exam=self.exam, classroom=self.classroom, subject=self.maths)
        self.practical_paper = ExamPaper.objects.create(exam=self.exam, classroom=self.classroom, subject=self.practical,
                                                        max_marks=50, pass_marks=17)

        def student(number, name):
            return Student.objects.create(school=self.school, admission_number=number, first_name=name,
                                          class_enrolled=self.classroom)

        self.kavya = student('G-1', 'Kavya')
        self.rahul = student('G-2', 'Rahul')
        self.meena = student('G-3', 'Meena')
        self.kavya.parents.add(self.parent)

    def marks(self, student, maths=None, practical=None, maths_absent=False):
        if maths is not None or maths_absent:
            Mark.objects.create(paper=self.maths_paper, student=student,
                                marks_obtained=None if maths_absent else maths, is_absent=maths_absent)
        if practical is not None:
            Mark.objects.create(paper=self.practical_paper, student=student, marks_obtained=practical)

    def rows(self):
        return {row['student_name']: row for row in compute_class_results(self.exam, self.classroom)['rows']}

    def test_subject_grades_use_each_papers_own_percentage(self):
        self.marks(self.kavya, maths=92, practical=41)   # 92 and 82 percent
        kavya = self.rows()['Kavya']
        by_subject = {s['subject']: s for s in kavya['subjects']}
        self.assertEqual((by_subject['Mathematics']['percentage'], by_subject['Mathematics']['grade']), (92.0, 'A1'))
        self.assertEqual((by_subject['Science Practical']['percentage'], by_subject['Science Practical']['grade']),
                         (82.0, 'A2'))
        # Overall: 133 of 150 = 88.7 percent
        self.assertEqual((kavya['percentage'], kavya['grade']), (88.7, 'A2'))

    def test_d_is_a_pass_at_33_percent(self):
        self.marks(self.rahul, maths=33, practical=17)
        rahul = self.rows()['Rahul']
        self.assertEqual(rahul['grade'], 'D')
        self.assertEqual(rahul['result'], 'PASS')

    def test_absent_subject_has_no_grade_but_counts_zero(self):
        self.marks(self.meena, maths_absent=True, practical=40)
        meena = self.rows()['Meena']
        maths = next(s for s in meena['subjects'] if s['subject'] == 'Mathematics')
        self.assertIsNone(maths['grade'])
        self.assertTrue(maths['is_absent'])
        self.assertEqual(meena['grade'], 'E')    # 40 of 150 = 26.7 percent
        self.assertEqual(meena['result'], 'FAIL')

    def test_incomplete_result_has_no_overall_grade(self):
        self.marks(self.kavya, maths=95)
        kavya = self.rows()['Kavya']
        self.assertIsNone(kavya['grade'])
        self.assertEqual(next(s for s in kavya['subjects'] if s['subject'] == 'Mathematics')['grade'], 'A1')

    def test_rank_ignores_grades(self):
        """Two students in the same grade band are still ranked by marks."""
        self.marks(self.kavya, maths=99, practical=48)   # 147
        self.marks(self.rahul, maths=92, practical=47)   # 139, also A1
        rows = self.rows()
        self.assertEqual((rows['Kavya']['grade'], rows['Kavya']['rank']), ('A1', 1))
        self.assertEqual((rows['Rahul']['grade'], rows['Rahul']['rank']), ('A1', 2))

    def test_school_scale_overrides_the_default(self):
        GradeBand.objects.bulk_create([
            GradeBand(school=self.school, label='Merit', min_percentage=75),
            GradeBand(school=self.school, label='Pass', min_percentage=35),
            GradeBand(school=self.school, label='Retry', min_percentage=0),
        ])
        self.marks(self.kavya, maths=80, practical=40)
        self.assertEqual(self.rows()['Kavya']['grade'], 'Merit')

    def test_grades_reach_the_parent_only_after_publishing(self):
        self.marks(self.kavya, maths=92, practical=41)
        self.marks(self.rahul, maths=50, practical=25)
        self.marks(self.meena, maths=40, practical=20)
        self.client.force_authenticate(user=self.parent)

        self.assertEqual(self.client.get(f'/api/v1/report-card/?student_id={self.kavya.id}').data['exams'], [])

        self.exam.is_published = True
        self.exam.save()
        card = self.client.get(f'/api/v1/report-card/?student_id={self.kavya.id}').data['exams'][0]
        self.assertEqual(card['grade'], 'A2')
        self.assertEqual({s['subject']: s['grade'] for s in card['subjects']},
                         {'Mathematics': 'A1', 'Science Practical': 'A2'})

    def test_teacher_and_admin_see_grades_before_publishing(self):
        self.marks(self.kavya, maths=92, practical=41)
        for user in (self.teacher, self.admin):
            self.client.force_authenticate(user=user)
            res = self.client.get(f'/api/v1/exams/{self.exam.id}/results/?class_id={self.classroom.id}')
            self.assertEqual(res.status_code, status.HTTP_200_OK)
            kavya = next(r for r in res.data['rows'] if r['student_name'] == 'Kavya')
            self.assertEqual(kavya['grade'], 'A2')

    def test_new_papers_default_to_a_33_pass_mark(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.post('/api/v1/exams/', {
            'name': 'Unit Test', 'academic_year': '2026-2027',
            'classroom_ids': [self.classroom.id], 'subject_ids': [self.maths.id],
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(ExamPaper.objects.get(exam_id=res.data['id']).pass_marks, 33)


class GradeScaleApiTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name='Scale School', code='SCL01')
        self.admin = User.objects.create_user(username='sc_admin', password='x', role=User.Role.ADMIN, school=self.school)
        self.teacher = User.objects.create_user(username='sc_teacher', password='x', role=User.Role.TEACHER, school=self.school)
        self.parent = User.objects.create_user(username='sc_parent', password='x', role=User.Role.PARENT, school=self.school)

    def test_anyone_signed_in_reads_the_default_scale(self):
        for user in (self.admin, self.teacher, self.parent):
            self.client.force_authenticate(user=user)
            res = self.client.get('/api/v1/grade-scale/')
            self.assertEqual(res.status_code, status.HTTP_200_OK)
            self.assertTrue(res.data['is_default'])
            self.assertEqual([b['label'] for b in res.data['bands']], ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'D', 'E'])

    def test_admin_replaces_the_scale(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.put('/api/v1/grade-scale/', {'bands': [
            {'label': 'A', 'min_percentage': 80, 'description': 'Great'},
            {'label': 'B', 'min_percentage': 50},
            {'label': 'C', 'min_percentage': 0},
        ]}, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertFalse(res.data['is_default'])
        self.assertEqual(GradeBand.objects.filter(school=self.school).count(), 3)

    def test_invalid_scale_changes_nothing(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.put('/api/v1/grade-scale/', {'bands': [
            {'label': 'A', 'min_percentage': 80}, {'label': 'B', 'min_percentage': 50},
        ]}, format='json')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('0%', res.data['detail'])
        self.assertFalse(GradeBand.objects.filter(school=self.school).exists())

    def test_teachers_and_parents_cannot_change_it(self):
        for user in (self.teacher, self.parent):
            self.client.force_authenticate(user=user)
            res = self.client.put('/api/v1/grade-scale/', {'bands': [{'label': 'A', 'min_percentage': 0}]},
                                  format='json')
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)


class DefaultScaleMigrationTests(APITestCase):
    def test_existing_schools_get_the_default_scale_once(self):
        migration = import_module('apps.exams.migrations.0003_seed_default_grade_bands')
        school = School.objects.create(name='Pre-existing', code='PRE01')
        migration.seed(global_apps, None)
        self.assertEqual(
            list(GradeBand.objects.filter(school=school).values_list('label', flat=True)),
            ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'D', 'E'],
        )
        migration.seed(global_apps, None)   # idempotent
        self.assertEqual(GradeBand.objects.filter(school=school).count(), 8)
