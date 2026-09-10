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
            name="Vivekananda School, Bagalur",
            code="VIV001",
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
        self.admin_a = User.objects.create_user(
            username="admin_a",
            password="Password@123",
            role=User.Role.ADMIN,
            school=self.school_a,
        )
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

        # Assign Teacher A to Class A1 ONLY
        self.class_a1.teachers.add(self.teacher_a)

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

    def test_teacher_can_create_homework_for_assigned_class(self):
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

    def test_teacher_cannot_create_homework_for_unassigned_class(self):
        self.client.force_authenticate(user=self.teacher_a)
        today = date.today()
        due = today + timedelta(days=3)

        # Attempt to create homework for Class A2 (unassigned)
        response = self.client.post('/api/v1/homework/', {
            'classroom': self.class_a2.id,
            'subject': 'Science',
            'title': 'Solar System',
            'description': 'Draw planets.',
            'assigned_date': str(today),
            'due_date': str(due),
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_due_date_in_past_fails(self):
        self.client.force_authenticate(user=self.teacher_a)
        today = date.today()
        past_due = today - timedelta(days=1)

        response = self.client.post('/api/v1/homework/', {
            'classroom': self.class_a1.id,
            'subject': 'History',
            'title': 'Past Events',
            'description': 'Ancient empires.',
            'due_date': str(past_due),
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('due_date', response.data)
        self.assertIn('past', str(response.data['due_date']))

    def test_assign_homework_to_specific_student(self):
        self.client.force_authenticate(user=self.teacher_a)
        today = date.today()
        due = today + timedelta(days=4)

        response = self.client.post('/api/v1/homework/', {
            'classroom': self.class_a1.id,
            'student': self.student_a.id,
            'subject': 'Mathematics',
            'title': 'Advanced Algebra Problem Set',
            'description': 'Targeted extra practice for Aarav.',
            'due_date': str(due),
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['student'], self.student_a.id)
        self.assertEqual(response.data['student_name'], 'Aarav Sharma')

        # Verify DB
        hw = Homework.objects.get(id=response.data['id'])
        self.assertEqual(hw.student, self.student_a)

    def test_assign_homework_to_student_from_different_class_fails(self):
        self.client.force_authenticate(user=self.teacher_a)
        today = date.today()
        due = today + timedelta(days=2)

        # Create another student in class A2
        student_other = Student.objects.create(
            school=self.school_a,
            admission_number="STU-099",
            first_name="Rohan",
            last_name="Verma",
            class_enrolled=self.class_a2,
        )

        response = self.client.post('/api/v1/homework/', {
            'classroom': self.class_a1.id,
            'student': student_other.id,
            'subject': 'Mathematics',
            'title': 'Mismatched Student HW',
            'due_date': str(due),
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('student', response.data)

    def test_teacher_can_update_own_assigned_class_homework(self):
        today = date.today()
        due = today + timedelta(days=3)
        hw = Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a1,
            subject='Science',
            title='Old Title',
            description='Old Description',
            assigned_by=self.teacher_a,
            assigned_date=today,
            due_date=due,
        )

        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.patch(f'/api/v1/homework/{hw.id}/', {
            'title': 'Updated Title',
        })
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['title'], 'Updated Title')

    def test_teacher_cannot_update_unassigned_class_homework(self):
        today = date.today()
        due = today + timedelta(days=3)
        hw = Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a2,
            subject='Science',
            title='Class 8 Science',
            description='Chapter 1',
            assigned_by=self.admin_a,
            assigned_date=today,
            due_date=due,
        )

        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.patch(f'/api/v1/homework/{hw.id}/', {
            'title': 'Hacked Title',
        })
        self.assertIn(response.status_code, [status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND])

    def test_teacher_can_delete_own_assigned_class_homework(self):
        today = date.today()
        due = today + timedelta(days=3)
        hw = Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a1,
            subject='Math',
            title='To be deleted',
            description='Will be removed',
            assigned_by=self.teacher_a,
            assigned_date=today,
            due_date=due,
        )

        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.delete(f'/api/v1/homework/{hw.id}/')
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Homework.objects.filter(id=hw.id).exists())

    def test_teacher_cannot_delete_unassigned_class_homework(self):
        today = date.today()
        due = today + timedelta(days=3)
        hw = Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a2,
            subject='History',
            title='Class 8 History',
            description='Chapter 5',
            assigned_by=self.admin_a,
            assigned_date=today,
            due_date=due,
        )

        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.delete(f'/api/v1/homework/{hw.id}/')
        self.assertIn(response.status_code, [status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND])
        self.assertTrue(Homework.objects.filter(id=hw.id).exists())

    def test_teacher_list_homework_only_shows_assigned_classes(self):
        today = date.today()
        due = today + timedelta(days=3)
        hw1 = Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a1,
            subject='Math',
            title='Class 5 Math',
            description='Ex 1',
            assigned_by=self.teacher_a,
            assigned_date=today,
            due_date=due,
        )
        Homework.objects.create(
            school=self.school_a,
            classroom=self.class_a2,
            subject='English',
            title='Class 8 English',
            description='Ex 2',
            assigned_by=self.admin_a,
            assigned_date=today,
            due_date=due,
        )

        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.get('/api/v1/homework/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['id'], hw1.id)

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
            assigned_by=self.admin_a,
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
