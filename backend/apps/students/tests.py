from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from rest_framework import status
from apps.schools.models import School
from apps.students.models import Class, Student

User = get_user_model()


class ClassAndStudentAPITests(APITestCase):
    def setUp(self):
        # Create two distinct schools
        self.school_a = School.objects.create(
            name="Vivekananda School, Bagalur",
            code="VIV001",
        )
        self.school_b = School.objects.create(
            name="XYZ International School",
            code="XYZ002",
        )

        # Create Admins
        self.admin_a = User.objects.create_user(
            username="admin_a",
            password="Password@123",
            role=User.Role.ADMIN,
            school=self.school_a,
        )
        self.admin_b = User.objects.create_user(
            username="admin_b",
            password="Password@123",
            role=User.Role.ADMIN,
            school=self.school_b,
        )

        # Create teachers belonging to each school
        self.teacher_a = User.objects.create_user(
            username="teacher_a",
            password="Password@123",
            role=User.Role.TEACHER,
            school=self.school_a,
        )
        self.teacher_b = User.objects.create_user(
            username="teacher_b",
            password="Password@123",
            role=User.Role.TEACHER,
            school=self.school_b,
        )

        # Parent in School A, used by the parent-link permission tests
        self.parent = User.objects.create_user(
            username="parent_a",
            password="Password@123",
            role=User.Role.PARENT,
            school=self.school_a,
        )

        # Classes in School A
        self.class_a1 = Class.objects.create(
            school=self.school_a,
            name="Grade 5",
            section="A",
            academic_year="2026-2027",
        )
        self.class_a1.teachers.add(self.teacher_a)

        self.class_a2 = Class.objects.create(
            school=self.school_a,
            name="Grade 8",
            section="B",
            academic_year="2026-2027",
        )

        # Class in School B
        self.class_b1 = Class.objects.create(
            school=self.school_b,
            name="Grade 10",
            section="A",
            academic_year="2026-2027",
        )

        # Students
        self.student_a1 = Student.objects.create(
            school=self.school_a,
            admission_number="STU-001",
            first_name="Aarav",
            last_name="Sharma",
            class_enrolled=self.class_a1,
        )
        self.student_a2 = Student.objects.create(
            school=self.school_a,
            admission_number="STU-002",
            first_name="Diya",
            last_name="Rao",
            class_enrolled=self.class_a2,
        )

    def test_unauthenticated_requests_are_rejected(self):
        response = self.client.get('/api/v1/classes/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

        response = self.client.get('/api/v1/students/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_admin_can_create_and_manage_classes_and_students(self):
        # Admin A creates class in School A
        self.client.force_authenticate(user=self.admin_a)
        res_class = self.client.post('/api/v1/classes/', {
            'name': 'Grade 12',
            'section': 'C',
            'academic_year': '2026-2027',
        })
        self.assertEqual(res_class.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res_class.data['school'], self.school_a.id)

        # Admin A creates student
        res_stu = self.client.post('/api/v1/students/', {
            'admission_number': 'STU-003',
            'first_name': 'Kavita',
            'last_name': 'Patel',
            'class_enrolled': self.class_a1.id,
        })
        self.assertEqual(res_stu.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res_stu.data['school'], self.school_a.id)

    def test_teacher_cannot_create_class(self):
        """Class creation is administrative; teachers are read-only here."""
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.post('/api/v1/classes/', {
            'name': 'Grade 7',
            'section': 'A',
            'academic_year': '2026-2027',
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Class.objects.filter(name='Grade 7', section='A').exists())

    def test_teacher_cannot_modify_or_delete_classes(self):
        """Not even the classes assigned to them - teachers only read classes."""
        self.client.force_authenticate(user=self.teacher_a)

        patch_assigned = self.client.patch(f'/api/v1/classes/{self.class_a1.id}/', {
            'name': 'Grade 5 Renamed',
        })
        self.assertEqual(patch_assigned.status_code, status.HTTP_403_FORBIDDEN)

        patch_unassigned = self.client.patch(f'/api/v1/classes/{self.class_a2.id}/', {
            'name': 'Grade 8 Renamed',
        })
        self.assertIn(patch_unassigned.status_code, [status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND])

        delete_res = self.client.delete(f'/api/v1/classes/{self.class_a1.id}/')
        self.assertEqual(delete_res.status_code, status.HTTP_403_FORBIDDEN)

        self.class_a1.refresh_from_db()
        self.assertEqual(self.class_a1.name, 'Grade 5')

    def test_teacher_sees_only_assigned_classes(self):
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.get('/api/v1/classes/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['id'], self.class_a1.id)
        self.assertEqual(results[0]['name'], 'Grade 5')

    def test_teacher_cannot_create_students(self):
        """Student admission is administrative, including for assigned classes."""
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.post('/api/v1/students/', {
            'admission_number': 'STU-004',
            'first_name': 'Rohan',
            'last_name': 'Mehta',
            'class_enrolled': self.class_a1.id,
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Student.objects.filter(admission_number='STU-004').exists())

    def test_teacher_cannot_modify_or_delete_students(self):
        """Teachers read students in their classes; they never edit them."""
        self.client.force_authenticate(user=self.teacher_a)

        patch_assigned = self.client.patch(f'/api/v1/students/{self.student_a1.id}/', {
            'last_name': 'Updated',
        })
        self.assertEqual(patch_assigned.status_code, status.HTTP_403_FORBIDDEN)

        patch_unassigned = self.client.patch(f'/api/v1/students/{self.student_a2.id}/', {
            'last_name': 'Hacked',
        })
        self.assertIn(patch_unassigned.status_code, [status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND])

        delete_res = self.client.delete(f'/api/v1/students/{self.student_a1.id}/')
        self.assertEqual(delete_res.status_code, status.HTTP_403_FORBIDDEN)

        self.student_a1.refresh_from_db()
        self.assertEqual(self.student_a1.last_name, 'Sharma')

    def test_teacher_cannot_assign_teachers_to_a_class(self):
        """Teacher assignment - including self-assignment - is admin only."""
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.patch(f'/api/v1/classes/{self.class_a2.id}/', {
            'teachers': [self.teacher_a.id],
        })
        self.assertIn(response.status_code, [status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND])
        self.assertFalse(self.class_a2.teachers.filter(id=self.teacher_a.id).exists())

    def test_teacher_cannot_manage_parent_links(self):
        """Linking and unlinking parents is admin only."""
        self.client.force_authenticate(user=self.teacher_a)
        link = self.client.post(
            f'/api/v1/students/{self.student_a1.id}/link-parent/',
            {'parent_id': self.parent.id},
        )
        self.assertEqual(link.status_code, status.HTTP_403_FORBIDDEN)

        unlink = self.client.post(
            f'/api/v1/students/{self.student_a1.id}/unlink-parent/',
            {'parent_id': self.parent.id},
        )
        self.assertEqual(unlink.status_code, status.HTTP_403_FORBIDDEN)

    def test_teacher_cannot_enroll_student_in_unassigned_class(self):
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.post(f'/api/v1/students/{self.student_a1.id}/enrollments/', {
            'classroom': self.class_a2.id,
            'academic_year': '2026-2027',
            'is_current': True,
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_teacher_sees_only_students_in_assigned_classes(self):
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.get('/api/v1/students/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['id'], self.student_a1.id)
        self.assertEqual(results[0]['admission_number'], 'STU-001')

        # Attempt retrieve of unassigned class student -> 404
        retrieve_res = self.client.get(f'/api/v1/students/{self.student_a2.id}/')
        self.assertEqual(retrieve_res.status_code, status.HTTP_404_NOT_FOUND)

    def test_prevent_cross_tenant_class_assignment(self):
        # Admin B from School B attempts to enroll student into Class from School A
        self.client.force_authenticate(user=self.admin_b)
        response = self.client.post('/api/v1/students/', {
            'admission_number': 'STU-999',
            'first_name': 'Sneha',
            'last_name': 'Patel',
            'class_enrolled': self.class_a1.id,
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('class_enrolled', response.data)
