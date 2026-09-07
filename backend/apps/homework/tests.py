from datetime import date, timedelta
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from rest_framework import status
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.homework.models import Homework

User = get_user_model()


class HomeworkAPITests(APITestCase):
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

        # Classes in School A
        self.class_a1 = Class.objects.create(
            school=self.school_a,
            name="Grade 5",
            section="A",
            academic_year="2026-2027",
        )
        self.class_a2 = Class.objects.create(
            school=self.school_a,
            name="Grade 8",
            section="B",
            academic_year="2026-2027",
        )

        # Class in School B
        self.class_b1 = Class.objects.create(
            school=self.school_b,
            name="Grade 5",
            section="A",
            academic_year="2026-2027",
        )

        # Users
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
        self.parent_a = User.objects.create_user(
            username="parent_a",
            password="Password@123",
            role=User.Role.PARENT,
            school=self.school_a,
        )

        # Student enrolled in Class A1 and linked to Parent A
        self.student_a = Student.objects.create(
            school=self.school_a,
            admission_number="STU-001",
            first_name="Aarav",
            last_name="Sharma",
            class_enrolled=self.class_a1,
        )
        self.student_a.parents.add(self.parent_a)

    def test_unauthenticated_request_rejected(self):
        response = self.client.get('/api/v1/homework/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

        response = self.client.post('/api/v1/homework/', {})
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_teacher_can_create_homework_for_own_school_class(self):
        self.client.force_authenticate(user=self.teacher_a)
        today = date.today()
        due = today + timedelta(days=3)

        response = self.client.post('/api/v1/homework/', {
            'classroom': self.class_a1.id,
            'subject': 'Mathematics',
            'title': 'Fractions and Decimals Exercise 2.1',
            'description': 'Complete questions 1 to 10 on page 45.',
            'assigned_date': str(today),
            'due_date': str(due),
        })

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['school'], self.school_a.id)
        self.assertEqual(response.data['classroom'], self.class_a1.id)
        self.assertEqual(response.data['subject'], 'Mathematics')

        # Check DB record
        homework = Homework.objects.get(id=response.data['id'])
        self.assertEqual(homework.assigned_by, self.teacher_a)
        self.assertEqual(homework.school, self.school_a)

    def test_teacher_cannot_use_another_schools_class(self):
        self.client.force_authenticate(user=self.teacher_a)
        today = date.today()
        due = today + timedelta(days=2)

        # Attempt to assign homework to School B's class
        response = self.client.post('/api/v1/homework/', {
            'classroom': self.class_b1.id,
            'subject': 'English',
            'title': 'Grammar Chapter 3',
            'description': 'Read and answer workbook questions.',
            'assigned_date': str(today),
            'due_date': str(due),
        })

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('classroom', response.data)

    def test_parent_can_view_relevant_homework(self):
        today = date.today()
        due = today + timedelta(days=2)

        # Homework 1: In Class A1 (Parent A's child class)
        hw1 = Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a1,
            subject='Science',
            title='Plant Life Cycle',
            description='Draw the flower parts.',
            assigned_by=self.teacher_a,
            assigned_date=today,
            due_date=due,
        )

        # Homework 2: In Class A2 (Different class, NOT Parent A's child class)
        Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a2,
            subject='History',
            title='Ancient Civilizations',
            description='Essay on Indus Valley.',
            assigned_by=self.teacher_a,
            assigned_date=today,
            due_date=due,
        )

        # Parent A requests homework list
        self.client.force_authenticate(user=self.parent_a)
        response = self.client.get('/api/v1/homework/')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['id'], hw1.id)
        self.assertEqual(results[0]['title'], 'Plant Life Cycle')

    def test_parent_cannot_access_another_schools_homework(self):
        today = date.today()
        due = today + timedelta(days=2)

        # Homework in School B
        hw_b = Homework.objects.create(
            school=self.school_b,
            classroom=self.class_b1,
            subject='Physics',
            title='Newton Laws',
            description='Solve problems 1-5.',
            assigned_by=self.teacher_b,
            assigned_date=today,
            due_date=due,
        )

        # Parent A attempts to view School B's homework directly
        self.client.force_authenticate(user=self.parent_a)
        response = self.client.get(f'/api/v1/homework/{hw_b.id}/')
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_due_date_cannot_be_earlier_than_assigned_date(self):
        self.client.force_authenticate(user=self.teacher_a)
        today = date.today()
        past_due = today - timedelta(days=2)

        response = self.client.post('/api/v1/homework/', {
            'classroom': self.class_a1.id,
            'subject': 'Mathematics',
            'title': 'Invalid Date Homework',
            'description': 'Test past due date.',
            'assigned_date': str(today),
            'due_date': str(past_due),
        })

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('due_date', response.data)
