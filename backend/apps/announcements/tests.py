from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase
from rest_framework import status
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.announcements.models import Announcement

User = get_user_model()


class AnnouncementAPITests(APITestCase):
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

        # Users in School A
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
        self.parent_a = User.objects.create_user(
            username="parent_a",
            password="Password@123",
            role=User.Role.PARENT,
            school=self.school_a,
        )

        # Users in School B
        self.teacher_b = User.objects.create_user(
            username="teacher_b",
            password="Password@123",
            role=User.Role.TEACHER,
            school=self.school_b,
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
        response = self.client.get('/api/v1/announcements/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

        response = self.client.post('/api/v1/announcements/', {})
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_admin_can_create_school_announcement(self):
        self.client.force_authenticate(user=self.admin_a)
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Annual Sports Day 2026',
            'content': 'All students must assemble at the ground by 8:00 AM.',
            'priority': 'URGENT',
            'audience_type': 'SCHOOL',
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['school'], self.school_a.id)
        self.assertEqual(response.data['audience_type'], 'SCHOOL')
        self.assertIsNone(response.data['target_class'])

    def test_admin_can_create_class_announcement(self):
        self.client.force_authenticate(user=self.admin_a)
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Grade 5 Parent Teacher Meeting',
            'content': 'PTM scheduled for Grade 5 this Saturday at 10 AM.',
            'priority': 'IMPORTANT',
            'audience_type': 'CLASS',
            'target_class': self.class_a1.id,
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['target_class'], self.class_a1.id)

    def test_teacher_can_create_announcement_in_own_school(self):
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Math Olympiad Registration',
            'content': 'Interested students please submit names by Friday.',
            'priority': 'NORMAL',
            'audience_type': 'SCHOOL',
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['school'], self.school_a.id)

    def test_teacher_cannot_target_another_schools_class(self):
        self.client.force_authenticate(user=self.teacher_a)
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Cross School Class Test',
            'content': 'Attempting to target School B class.',
            'priority': 'NORMAL',
            'audience_type': 'CLASS',
            'target_class': self.class_b1.id,
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('target_class', response.data)

    def test_parent_can_view_school_announcement(self):
        ann = Announcement.objects.create(
            school=self.school_a,
            title='Holiday Notice',
            content='School closed on Friday.',
            priority='IMPORTANT',
            audience_type='SCHOOL',
            created_by=self.admin_a,
        )
        self.client.force_authenticate(user=self.parent_a)
        response = self.client.get('/api/v1/announcements/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        ids = [item['id'] for item in results]
        self.assertIn(ann.id, ids)

    def test_parent_can_view_child_class_announcement(self):
        # Class A1 announcement (Parent A's child is in Class A1)
        ann_child = Announcement.objects.create(
            school=self.school_a,
            title='Class 5-A Science Fair',
            content='Projects due on Monday.',
            priority='NORMAL',
            audience_type='CLASS',
            target_class=self.class_a1,
            created_by=self.teacher_a,
        )
        self.client.force_authenticate(user=self.parent_a)
        response = self.client.get('/api/v1/announcements/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        ids = [item['id'] for item in results]
        self.assertIn(ann_child.id, ids)

    def test_parent_cannot_view_unrelated_class_announcement(self):
        # Class A2 announcement (Parent A has no child in Class A2)
        ann_other = Announcement.objects.create(
            school=self.school_a,
            title='Class 8-B Notice',
            content='Class 8 specific circular.',
            priority='NORMAL',
            audience_type='CLASS',
            target_class=self.class_a2,
            created_by=self.teacher_a,
        )
        self.client.force_authenticate(user=self.parent_a)
        response = self.client.get('/api/v1/announcements/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        ids = [item['id'] for item in results]
        self.assertNotIn(ann_other.id, ids)

        # Direct retrieve returns 404
        direct_res = self.client.get(f'/api/v1/announcements/{ann_other.id}/')
        self.assertEqual(direct_res.status_code, status.HTTP_404_NOT_FOUND)

    def test_parent_cannot_create_announcement(self):
        self.client.force_authenticate(user=self.parent_a)
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Parent Post',
            'content': 'Attempting unauthorized write.',
            'priority': 'NORMAL',
            'audience_type': 'SCHOOL',
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_cross_school_announcement_access_rejected(self):
        ann_b = Announcement.objects.create(
            school=self.school_b,
            title='School B Circular',
            content='Confidential to School B.',
            priority='URGENT',
            audience_type='SCHOOL',
            created_by=self.teacher_b,
        )
        self.client.force_authenticate(user=self.parent_a)
        response = self.client.get(f'/api/v1/announcements/{ann_b.id}/')
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_invalid_class_announcement_without_target_class_rejected(self):
        self.client.force_authenticate(user=self.admin_a)
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Missing Target Class',
            'content': 'CLASS audience but no target_class given.',
            'priority': 'NORMAL',
            'audience_type': 'CLASS',
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('target_class', response.data)

    def test_school_announcement_with_target_class_rejected(self):
        self.client.force_authenticate(user=self.admin_a)
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Contradictory Audience',
            'content': 'SCHOOL audience but target_class is provided.',
            'priority': 'NORMAL',
            'audience_type': 'SCHOOL',
            'target_class': self.class_a1.id,
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('target_class', response.data)

    def test_invalid_attachment_type_rejected(self):
        self.client.force_authenticate(user=self.admin_a)
        bad_file = SimpleUploadedFile(
            "malicious.exe",
            b"binary executable contents",
            content_type="application/octet-stream",
        )
        response = self.client.post('/api/v1/announcements/', {
            'title': 'Executable Attachment Test',
            'content': 'Attempting to upload executable.',
            'priority': 'NORMAL',
            'audience_type': 'SCHOOL',
            'attachment': bad_file,
        }, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('attachment', response.data)

    def test_priority_filtering_works(self):
        Announcement.objects.create(
            school=self.school_a,
            title='Normal Circular',
            content='General info.',
            priority='NORMAL',
            audience_type='SCHOOL',
            created_by=self.admin_a,
        )
        urgent_ann = Announcement.objects.create(
            school=self.school_a,
            title='Urgent Alert',
            content='Immediate action required.',
            priority='URGENT',
            audience_type='SCHOOL',
            created_by=self.admin_a,
        )

        self.client.force_authenticate(user=self.admin_a)
        response = self.client.get('/api/v1/announcements/?priority=URGENT')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['id'], urgent_ann.id)
        self.assertEqual(results[0]['priority'], 'URGENT')
