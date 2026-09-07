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
            name="ABC Matriculation School",
            code="ABC001",
        )
        self.school_b = School.objects.create(
            name="XYZ International School",
            code="XYZ002",
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

    def test_unauthenticated_requests_are_rejected(self):
        response = self.client.get('/api/v1/classes/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

        response = self.client.get('/api/v1/students/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_create_and_list_classes_with_tenant_isolation(self):
        # Teacher A creates a class in School A
        self.client.force_authenticate(user=self.teacher_a)
        res_a = self.client.post('/api/v1/classes/', {
            'name': 'Grade 5',
            'section': 'A',
            'academic_year': '2026-2027',
        })
        self.assertEqual(res_a.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res_a.data['school'], self.school_a.id)

        # Teacher B creates a class in School B
        self.client.force_authenticate(user=self.teacher_b)
        res_b = self.client.post('/api/v1/classes/', {
            'name': 'Grade 10',
            'section': 'B',
            'academic_year': '2026-2027',
        })
        self.assertEqual(res_b.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res_b.data['school'], self.school_b.id)

        # Teacher A lists classes -> must only see School A's class
        self.client.force_authenticate(user=self.teacher_a)
        list_a = self.client.get('/api/v1/classes/')
        self.assertEqual(list_a.status_code, status.HTTP_200_OK)
        # Results can be a list or paginated dict
        results_a = list_a.data.get('results', list_a.data)
        self.assertEqual(len(results_a), 1)
        self.assertEqual(results_a[0]['name'], 'Grade 5')

        # Teacher B lists classes -> must only see School B's class
        self.client.force_authenticate(user=self.teacher_b)
        list_b = self.client.get('/api/v1/classes/')
        self.assertEqual(list_b.status_code, status.HTTP_200_OK)
        results_b = list_b.data.get('results', list_b.data)
        self.assertEqual(len(results_b), 1)
        self.assertEqual(results_b[0]['name'], 'Grade 10')

    def test_create_and_manage_students_with_tenant_isolation(self):
        # Setup classes
        class_a = Class.objects.create(
            school=self.school_a,
            name='Grade 6',
            section='B',
            academic_year='2026-2027',
        )
        class_b = Class.objects.create(
            school=self.school_b,
            name='Grade 7',
            section='A',
            academic_year='2026-2027',
        )

        # Teacher A creates student in School A
        self.client.force_authenticate(user=self.teacher_a)
        create_res = self.client.post('/api/v1/students/', {
            'admission_number': 'STU-001',
            'first_name': 'Aarav',
            'last_name': 'Sharma',
            'date_of_birth': '2014-05-12',
            'class_enrolled': class_a.id,
        })
        self.assertEqual(create_res.status_code, status.HTTP_201_CREATED)
        student_id = create_res.data['id']
        self.assertEqual(create_res.data['school'], self.school_a.id)

        # Teacher B attempts to view or list students -> receives 0 students
        self.client.force_authenticate(user=self.teacher_b)
        list_res = self.client.get('/api/v1/students/')
        self.assertEqual(list_res.status_code, status.HTTP_200_OK)
        results = list_res.data.get('results', list_res.data)
        self.assertEqual(len(results), 0)

        # Teacher B attempts to retrieve Teacher A's student directly -> 404 Not Found
        retrieve_res = self.client.get(f'/api/v1/students/{student_id}/')
        self.assertEqual(retrieve_res.status_code, status.HTTP_404_NOT_FOUND)

        # Teacher A retrieves and updates their own student -> 200 OK
        self.client.force_authenticate(user=self.teacher_a)
        update_res = self.client.patch(f'/api/v1/students/{student_id}/', {
            'last_name': 'Kumar',
        })
        self.assertEqual(update_res.status_code, status.HTTP_200_OK)
        self.assertEqual(update_res.data['last_name'], 'Kumar')

    def test_prevent_cross_tenant_class_assignment(self):
        # Class in School A
        class_a = Class.objects.create(
            school=self.school_a,
            name='Grade 1',
            section='A',
            academic_year='2026-2027',
        )

        # Teacher B from School B attempts to enroll student into Class from School A
        self.client.force_authenticate(user=self.teacher_b)
        response = self.client.post('/api/v1/students/', {
            'admission_number': 'STU-999',
            'first_name': 'Sneha',
            'last_name': 'Patel',
            'class_enrolled': class_a.id,
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('class_enrolled', response.data)
