"""Tests for bulk roll onboarding from a CSV."""

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.test import APITestCase

from apps.schools.models import School
from apps.students.models import Class, Student

User = get_user_model()

YEAR = '2026-2027'

HEADER = (
    'admission_number,first_name,last_name,class_name,section,'
    'date_of_birth,parent_name,parent_phone,parent_email\n'
)


def csv_upload(body, name='roll.csv'):
    return SimpleUploadedFile(name, body.encode('utf-8'), content_type='text/csv')


class StudentImportTests(APITestCase):
    def setUp(self):
        self.school = School.objects.create(name="Import School", code="IMP01")
        self.admin = User.objects.create_user(
            username='import_admin', password='Password@123',
            role=User.Role.ADMIN, school=self.school,
        )
        self.teacher = User.objects.create_user(
            username='import_teacher', password='Password@123',
            role=User.Role.TEACHER, school=self.school,
        )
        self.client.force_authenticate(user=self.admin)

    def _post(self, body, **extra):
        payload = {'file': csv_upload(body), 'academic_year': YEAR}
        payload.update(extra)
        return self.client.post('/api/v1/students/import/', payload, format='multipart')

    # ------------------------------------------------------------------
    # the happy path
    # ------------------------------------------------------------------

    def test_import_creates_classes_students_and_parents(self):
        body = HEADER + (
            'ADM001,Kavya,Sundaram,Grade 5,A,2015-04-12,Ravi Kumar,9876543210,ravi@example.com\n'
            'ADM002,Rahul,Murugan,Grade 5,A,,Latha Murugan,9876543211,\n'
            'ADM003,Ananya,Krishnan,Grade 6,B,,,,\n'
        )
        res = self._post(body)

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['students_created'], 3)
        self.assertEqual(res.data['classes_created'], 2)
        self.assertEqual(res.data['parents_created'], 2)
        self.assertEqual(res.data['parents_linked'], 2)
        self.assertEqual(res.data['errors'], [])

        self.assertEqual(Student.objects.filter(school=self.school).count(), 3)
        self.assertTrue(Class.objects.filter(
            school=self.school, name='Grade 5', section='A', academic_year=YEAR).exists())

        kavya = Student.objects.get(admission_number='ADM001')
        self.assertEqual(kavya.class_enrolled.name, 'Grade 5')
        self.assertEqual(kavya.parents.count(), 1)
        self.assertEqual(str(kavya.date_of_birth), '2015-04-12')

    def test_a_parent_with_two_children_is_created_once_and_linked_twice(self):
        body = HEADER + (
            'ADM010,Arun,K,Grade 5,A,,Suresh K,9000011111,\n'
            'ADM011,Divya,K,Grade 7,C,,Suresh K,9000011111,\n'
        )
        res = self._post(body)

        self.assertEqual(res.data['parents_created'], 1)
        self.assertEqual(res.data['parents_linked'], 2)

        parent = User.objects.get(role=User.Role.PARENT, phone_number='9000011111')
        self.assertEqual(parent.children.count(), 2)

    def test_parent_accounts_have_no_usable_password(self):
        """They sign in with the WhatsApp code, so no password is distributed."""
        self._post(HEADER + 'ADM020,Meena,R,Grade 5,A,,Gopal R,9000022222,\n')

        parent = User.objects.get(phone_number='9000022222')
        self.assertFalse(parent.has_usable_password())
        self.assertEqual(parent.school, self.school)

    def test_phone_numbers_are_normalised(self):
        body = HEADER + (
            'ADM030,A,B,Grade 5,A,,P One,+91 98765 43299,\n'
            'ADM031,C,D,Grade 5,A,,P One,9876543299,\n'
        )
        res = self._post(body)

        # Both rows name the same parent written two ways.
        self.assertEqual(res.data['parents_created'], 1)
        self.assertEqual(User.objects.filter(phone_number='9876543299').count(), 1)

    # ------------------------------------------------------------------
    # re-running a corrected file
    # ------------------------------------------------------------------

    def test_reimport_updates_instead_of_duplicating(self):
        self._post(HEADER + 'ADM040,Kavya,Sundram,Grade 5,A,,,,\n')
        res = self._post(HEADER + 'ADM040,Kavya,Sundaram,Grade 5,B,,,,\n')

        self.assertEqual(res.data['students_created'], 0)
        self.assertEqual(res.data['students_updated'], 1)
        self.assertEqual(Student.objects.filter(admission_number='ADM040').count(), 1)

        student = Student.objects.get(admission_number='ADM040')
        self.assertEqual(student.last_name, 'Sundaram')
        self.assertEqual(student.class_enrolled.section, 'B')

    # ------------------------------------------------------------------
    # bad files
    # ------------------------------------------------------------------

    def test_missing_required_column_is_rejected(self):
        res = self._post('first_name,last_name\nKavya,S\n')

        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('admission_number', res.data['detail'])

    def test_rows_with_problems_are_reported_by_line_number(self):
        body = HEADER + (
            'ADM050,Valid,Row,Grade 5,A,,,,\n'
            ',Missing,Admission,Grade 5,A,,,,\n'
            'ADM052,,NoFirstName,Grade 5,A,,,,\n'
            'ADM050,Duplicate,InFile,Grade 5,A,,,,\n'
        )
        res = self._post(body)

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['students_created'], 1)

        rows = {error['row'] for error in res.data['errors']}
        self.assertEqual(rows, {3, 4, 5})
        messages = ' '.join(error['message'] for error in res.data['errors'])
        self.assertIn('admission_number is required', messages)
        self.assertIn('first_name is required', messages)
        self.assertIn('Duplicate', messages)

    def test_bad_date_is_reported_but_the_student_is_still_created(self):
        res = self._post(HEADER + 'ADM060,Kavya,S,Grade 5,A,12-04-2015,,,\n')

        self.assertEqual(res.data['students_created'], 1)
        self.assertIn('date_of_birth', res.data['errors'][0]['message'])
        self.assertIsNone(Student.objects.get(admission_number='ADM060').date_of_birth)

    def test_empty_file_is_rejected(self):
        res = self._post('')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    # ------------------------------------------------------------------
    # dry run
    # ------------------------------------------------------------------

    def test_dry_run_reports_without_writing(self):
        body = HEADER + (
            'ADM070,Kavya,S,Grade 5,A,,Ravi,9000033333,\n'
            'ADM071,Rahul,M,Grade 5,A,,,,\n'
        )
        res = self._post(body, dry_run='true')

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.data['dry_run'])
        self.assertEqual(res.data['students_created'], 2)

        # Nothing was kept.
        self.assertEqual(Student.objects.filter(school=self.school).count(), 0)
        self.assertFalse(User.objects.filter(phone_number='9000033333').exists())

    # ------------------------------------------------------------------
    # access
    # ------------------------------------------------------------------

    def test_teacher_cannot_import(self):
        self.client.force_authenticate(user=self.teacher)
        res = self._post(HEADER + 'ADM080,X,Y,Grade 5,A,,,,\n')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_unauthenticated_cannot_import(self):
        self.client.force_authenticate(user=None)
        res = self._post(HEADER + 'ADM081,X,Y,Grade 5,A,,,,\n')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_admin_can_download_the_template(self):
        res = self.client.get('/api/v1/students/import/')

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res['Content-Type'], 'text/csv')
        body = res.content.decode('utf-8')
        self.assertIn('admission_number', body.splitlines()[0])
        self.assertIn('parent_phone', body.splitlines()[0])

    def test_teacher_cannot_download_the_template(self):
        self.client.force_authenticate(user=self.teacher)
        res = self.client.get('/api/v1/students/import/')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    # ------------------------------------------------------------------
    # scale
    # ------------------------------------------------------------------

    def test_a_thousand_row_roll_imports(self):
        rows = ''.join(
            f'ADM{index:05d},Student{index},Family,Grade {index % 12 + 1},'
            f'{chr(ord("A") + index % 4)},,Parent{index % 400},'
            f'9{index % 400:09d},\n'
            for index in range(1000)
        )
        res = self._post(HEADER + rows)

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['students_created'], 1000)
        self.assertEqual(res.data['errors'], [])
        self.assertEqual(Student.objects.filter(school=self.school).count(), 1000)
