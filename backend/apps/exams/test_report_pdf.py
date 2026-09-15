"""The printable report card: real data, and the same access rules as the API."""

from datetime import date

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.attendance.models import Attendance
from apps.exams.models import Exam, ExamPaper, Mark
from apps.exams.pdf import render_report_card_pdf
from apps.exams.services import report_card
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.timetable.models import Subject

User = get_user_model()


class ReportCardPdfTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name='Aaa Printable School', code='PDF01', address='Bagalur',
                                            contact_phone='+91 90000 00000')
        self.other_school = School.objects.create(name='Zzz Other', code='PDF02')

        def user(username, role, school=None, **extra):
            return User.objects.create_user(username=username, password='x', role=role,
                                            school=school or self.school, **extra)

        self.admin = user('pdf_admin', User.Role.ADMIN)
        self.teacher = user('pdf_teacher', User.Role.TEACHER, first_name='Priya', last_name='Sharma')
        self.other_teacher = user('pdf_other_teacher', User.Role.TEACHER)
        self.parent = user('pdf_parent', User.Role.PARENT)
        self.other_parent = user('pdf_other_parent', User.Role.PARENT)

        self.classroom = Class.objects.create(school=self.school, name='Grade 5', section='A',
                                              academic_year='2026-2027', class_teacher=self.teacher)
        self.classroom.teachers.add(self.teacher)
        self.other_class = Class.objects.create(school=self.school, name='Grade 6', section='B',
                                                academic_year='2026-2027')
        self.other_class.teachers.add(self.other_teacher)

        self.kavya = Student.objects.create(school=self.school, admission_number='VSB-501', first_name='Kavya',
                                            last_name='Sundaram', class_enrolled=self.classroom)
        self.kavya.parents.add(self.parent)
        self.rahul = Student.objects.create(school=self.school, admission_number='VSB-601', first_name='Rahul',
                                            class_enrolled=self.other_class)
        self.rahul.parents.add(self.other_parent)
        self.stranger = Student.objects.create(school=self.other_school, admission_number='X-1', first_name='Other')

        self.maths = Subject.objects.create(school=self.school, name='Mathematics')
        self.science = Subject.objects.create(school=self.school, name='Science')

        self.published = Exam.objects.create(school=self.school, name='Unit Test 1', academic_year='2026-2027',
                                             is_published=True)
        self.draft = Exam.objects.create(school=self.school, name='Quarterly Draft', academic_year='2026-2027')
        for exam in (self.published, self.draft):
            maths = ExamPaper.objects.create(exam=exam, classroom=self.classroom, subject=self.maths)
            science = ExamPaper.objects.create(exam=exam, classroom=self.classroom, subject=self.science)
            Mark.objects.create(paper=maths, student=self.kavya, marks_obtained=92)
            Mark.objects.create(paper=science, student=self.kavya, marks_obtained=78)
        rahul_paper = ExamPaper.objects.create(exam=self.published, classroom=self.other_class, subject=self.maths)
        Mark.objects.create(paper=rahul_paper, student=self.rahul, marks_obtained=55)

        Attendance.objects.create(school=self.school, student=self.kavya, classroom=self.classroom,
                                  date=date(2026, 9, 1), status='PRESENT', marked_by=self.teacher)
        Attendance.objects.create(school=self.school, student=self.kavya, classroom=self.classroom,
                                  date=date(2026, 9, 2), status='ABSENT', marked_by=self.teacher)

    def get_pdf(self, user, student, exam=None):
        self.client.force_authenticate(user=user)
        url = f'/api/v1/report-card/pdf/?student_id={student.id}'
        if exam is not None:
            url += f'&exam_id={exam.id}'
        return self.client.get(url)

    # -- content ------------------------------------------------------------------

    def test_pdf_is_built_from_the_database(self):
        cards = report_card(self.kavya, published_only=False)
        pdf = render_report_card_pdf(school=self.school, student=self.kavya, cards=cards, compress=False)

        self.assertTrue(pdf.startswith(b'%PDF'))
        for expected in (b'Aaa Printable School', b'Kavya Sundaram', b'VSB-501', b'Grade 5', b'2026-2027',
                         b'Priya Sharma', b'Unit Test 1', b'Mathematics', b'Science', b'92', b'78', b'170',
                         b'85', b'A2', b'A1', b'B1', b'Pass', b'1st of 1', b'50.0% \\(1 of 2 days\\)'):
            self.assertIn(expected, pdf, expected)

    def test_draft_results_are_marked_as_draft(self):
        cards = [c for c in report_card(self.kavya, published_only=False) if c['exam'] == self.draft.id]
        pdf = render_report_card_pdf(school=self.school, student=self.kavya, cards=cards, compress=False)
        self.assertIn(b'DRAFT', pdf)
        published = [c for c in report_card(self.kavya, published_only=False) if c['exam'] == self.published.id]
        self.assertNotIn(b'DRAFT', render_report_card_pdf(school=self.school, student=self.kavya, cards=published,
                                                          compress=False))

    # -- admin ------------------------------------------------------------------------

    def test_admin_downloads_any_students_report_card(self):
        res = self.get_pdf(self.admin, self.kavya)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res['Content-Type'], 'application/pdf')
        self.assertTrue(res.content.startswith(b'%PDF'))
        self.assertIn('report-card-vsb-501-all-exams.pdf', res['Content-Disposition'])
        self.assertEqual(res['Cache-Control'], 'private, no-store')

    def test_admin_one_exam(self):
        res = self.get_pdf(self.admin, self.kavya, self.draft)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('quarterly-draft', res['Content-Disposition'])

    def test_admin_cannot_reach_another_schools_student(self):
        self.assertEqual(self.get_pdf(self.admin, self.stranger).status_code, status.HTTP_404_NOT_FOUND)

    # -- teacher ----------------------------------------------------------------------

    def test_teacher_downloads_own_class_student(self):
        self.assertEqual(self.get_pdf(self.teacher, self.kavya).status_code, status.HTTP_200_OK)

    def test_teacher_blocked_from_unrelated_student(self):
        self.assertEqual(self.get_pdf(self.teacher, self.rahul).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.get_pdf(self.other_teacher, self.kavya).status_code, status.HTTP_403_FORBIDDEN)

    # -- parent -----------------------------------------------------------------------

    def test_parent_downloads_own_childs_published_report_card(self):
        res = self.get_pdf(self.parent, self.kavya, self.published)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.content.startswith(b'%PDF'))

    def test_parent_cannot_download_an_unpublished_exam(self):
        self.assertEqual(self.get_pdf(self.parent, self.kavya, self.draft).status_code, status.HTTP_404_NOT_FOUND)

    def test_parent_all_exams_pdf_holds_only_published_exams(self):
        from apps.exams import views

        captured = {}
        original = views.render_report_card_pdf

        def spy(**kwargs):
            captured['cards'] = kwargs['cards']
            return original(**kwargs)

        views.render_report_card_pdf = spy
        try:
            res = self.get_pdf(self.parent, self.kavya)
        finally:
            views.render_report_card_pdf = original
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual([c['exam_name'] for c in captured['cards']], ['Unit Test 1'])

    def test_parent_blocked_from_another_child_by_changing_the_id(self):
        self.assertEqual(self.get_pdf(self.parent, self.rahul).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.get_pdf(self.parent, self.rahul, self.published).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.get_pdf(self.parent, self.stranger).status_code, status.HTTP_404_NOT_FOUND)

    def test_exam_of_a_different_student_is_not_found(self):
        other_exam = Exam.objects.create(school=self.school, name='Grade 6 only', academic_year='2026-2027',
                                         is_published=True)
        ExamPaper.objects.create(exam=other_exam, classroom=self.other_class, subject=self.science)
        self.assertEqual(self.get_pdf(self.admin, self.kavya, other_exam).status_code, status.HTTP_404_NOT_FOUND)

    def test_requires_sign_in_and_a_student(self):
        self.client.force_authenticate(user=None)
        self.assertEqual(self.client.get(f'/api/v1/report-card/pdf/?student_id={self.kavya.id}').status_code,
                         status.HTTP_401_UNAUTHORIZED)
        self.client.force_authenticate(user=self.admin)
        self.assertEqual(self.client.get('/api/v1/report-card/pdf/').status_code, status.HTTP_400_BAD_REQUEST)
