from datetime import date, timedelta
from django.contrib.auth import get_user_model
from django.core import mail
from rest_framework import status
from rest_framework.test import APITestCase
from apps.schools.models import School
from apps.students.models import Class, Student
from apps.homework.models import Homework
from apps.announcements.models import Announcement
from apps.notifications.models import Notification

User = get_user_model()


class WorkflowIntegrationTests(APITestCase):
    def setUp(self):
        mail.outbox.clear()

        # Dedicated School
        self.school = School.objects.create(
            name="Vivekananda School, Bagalur",
            code="VIV001",
            contact_phone="9443940772",
        )

        # Classes
        self.class_5a = Class.objects.create(
            school=self.school,
            name="Grade 5",
            section="A",
            academic_year="2026-2027",
        )
        self.class_6a = Class.objects.create(
            school=self.school,
            name="Grade 6",
            section="A",
            academic_year="2026-2027",
        )
        self.class_7b = Class.objects.create(
            school=self.school,
            name="Grade 7",
            section="B",
            academic_year="2026-2027",
        )

        # Users
        self.admin_user = User.objects.create_user(
            username="admin_kumar",
            email="admin@schoolconnect.edu",
            password="AdminPassword@123",
            role=User.Role.ADMIN,
            school=self.school,
        )

        self.teacher_priya = User.objects.create_user(
            username="teacher_priya",
            email="priya@schoolconnect.edu",
            password="TeacherPassword@123",
            role=User.Role.TEACHER,
            school=self.school,
            first_name="Priya",
            last_name="Sharma",
        )
        # Assign Grade 5-A to Teacher Priya
        self.class_5a.teachers.add(self.teacher_priya)

        self.teacher_anand = User.objects.create_user(
            username="teacher_anand",
            email="anand@schoolconnect.edu",
            password="TeacherPassword@123",
            role=User.Role.TEACHER,
            school=self.school,
            first_name="Anand",
            last_name="Verma",
        )
        # Assign Grade 6-A to Teacher Anand
        self.class_6a.teachers.add(self.teacher_anand)

        # Parent 1: Kumar (has child Kavitha in 5-A and child Arjun in 7-B)
        self.parent_kumar = User.objects.create_user(
            username="parent_kumar",
            email="kumar.parent@example.com",
            password="ParentPassword@123",
            role=User.Role.PARENT,
            school=self.school,
            first_name="Kumar",
            last_name="Ramasamy",
        )

        # Parent 2: Suresh (has child Rahul in 6-A)
        self.parent_suresh = User.objects.create_user(
            username="parent_suresh",
            email="suresh.parent@example.com",
            password="ParentPassword@123",
            role=User.Role.PARENT,
            school=self.school,
            first_name="Suresh",
            last_name="Babu",
        )

        # Parent 3: Meena (has twins in 5-A: child Twins1 and Twins2)
        self.parent_meena = User.objects.create_user(
            username="parent_meena",
            email="meena.parent@example.com",
            password="ParentPassword@123",
            role=User.Role.PARENT,
            school=self.school,
            first_name="Meena",
            last_name="Kumari",
        )

        # Students
        self.student_kavitha = Student.objects.create(
            school=self.school,
            admission_number="VIV-501",
            first_name="Kavitha",
            last_name="Kumar",
            class_enrolled=self.class_5a,
        )
        self.student_kavitha.parents.add(self.parent_kumar)

        self.student_arjun = Student.objects.create(
            school=self.school,
            admission_number="VIV-701",
            first_name="Arjun",
            last_name="Kumar",
            class_enrolled=self.class_7b,
        )
        self.student_arjun.parents.add(self.parent_kumar)

        self.student_rahul = Student.objects.create(
            school=self.school,
            admission_number="VIV-601",
            first_name="Rahul",
            last_name="Suresh",
            class_enrolled=self.class_6a,
        )
        self.student_rahul.parents.add(self.parent_suresh)

        # Meena's twins in 5-A
        self.student_twin1 = Student.objects.create(
            school=self.school,
            admission_number="VIV-502",
            first_name="Diya",
            last_name="Meena",
            class_enrolled=self.class_5a,
        )
        self.student_twin1.parents.add(self.parent_meena)

        self.student_twin2 = Student.objects.create(
            school=self.school,
            admission_number="VIV-503",
            first_name="Deepak",
            last_name="Meena",
            class_enrolled=self.class_5a,
        )
        self.student_twin2.parents.add(self.parent_meena)

    # 1. Parent can see linked child
    def test_01_parent_can_see_linked_child(self):
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/parent/children/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        adm_numbers = [c['admission_number'] for c in res.data]
        self.assertIn('VIV-501', adm_numbers)
        self.assertIn('VIV-701', adm_numbers)
        self.assertEqual(len(res.data), 2)

    # 2. Parent cannot see unrelated student
    def test_02_parent_cannot_see_unrelated_student(self):
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/students/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        adm_numbers = [s['admission_number'] for s in results]
        # Kumar must NOT see Rahul (VIV-601)
        self.assertNotIn('VIV-601', adm_numbers)
        self.assertIn('VIV-501', adm_numbers)

    # 3. Parent sees homework for child's class
    def test_03_parent_sees_homework_for_child_class(self):
        hw_5a = Homework.objects.create(
            school=self.school,
            classroom=self.class_5a,
            subject="Mathematics",
            title="Algebra Exercises",
            due_date=date.today() + timedelta(days=2),
            assigned_by=self.teacher_priya,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/homework/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        hw_ids = [h['id'] for h in results]
        self.assertIn(hw_5a.id, hw_ids)

    # 4. Parent cannot see homework for unrelated class
    def test_04_parent_cannot_see_homework_for_unrelated_class(self):
        hw_6a = Homework.objects.create(
            school=self.school,
            classroom=self.class_6a,
            subject="Social Science",
            title="Civics Chapter 2",
            due_date=date.today() + timedelta(days=2),
            assigned_by=self.teacher_anand,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/homework/')
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        hw_ids = [h['id'] for h in results]
        self.assertNotIn(hw_6a.id, hw_ids)

    # 5. Parent cannot bypass homework filtering using class_id
    def test_05_parent_cannot_bypass_homework_filtering_using_class_id(self):
        Homework.objects.create(
            school=self.school,
            classroom=self.class_6a,
            subject="Social Science",
            title="Civics Chapter 2",
            due_date=date.today() + timedelta(days=2),
            assigned_by=self.teacher_anand,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        # Attempting to explicitly query class 6-A
        res = self.client.get(f'/api/v1/homework/?class_id={self.class_6a.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        self.assertEqual(len(results), 0)

    # 6. Parent cannot access unrelated homework detail
    def test_06_parent_cannot_access_unrelated_homework_detail(self):
        hw_6a = Homework.objects.create(
            school=self.school,
            classroom=self.class_6a,
            subject="Social Science",
            title="Civics Chapter 2",
            due_date=date.today() + timedelta(days=2),
            assigned_by=self.teacher_anand,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get(f'/api/v1/homework/{hw_6a.id}/')
        # Returns 404 Not Found to prevent data leakage
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    # 7. Parent sees school-wide announcements
    def test_07_parent_sees_school_wide_announcements(self):
        ann_school = Announcement.objects.create(
            school=self.school,
            title="Annual Sports Day 2026",
            content="Sports Day will be held on Nov 14.",
            audience_type=Announcement.AudienceType.SCHOOL,
            created_by=self.admin_user,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/announcements/')
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        ids = [a['id'] for a in results]
        self.assertIn(ann_school.id, ids)

    # 8. Parent sees announcements for child's class
    def test_08_parent_sees_announcements_for_child_class(self):
        ann_5a = Announcement.objects.create(
            school=self.school,
            title="Grade 5-A Science Model Presentation",
            content="Please bring chart papers.",
            audience_type=Announcement.AudienceType.CLASS,
            target_class=self.class_5a,
            created_by=self.teacher_priya,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/announcements/')
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        ids = [a['id'] for a in results]
        self.assertIn(ann_5a.id, ids)

    # 9. Parent cannot see another class announcement
    def test_09_parent_cannot_see_another_class_announcement(self):
        ann_6a = Announcement.objects.create(
            school=self.school,
            title="Grade 6-A Parent Teacher Meet",
            content="Meeting on Friday.",
            audience_type=Announcement.AudienceType.CLASS,
            target_class=self.class_6a,
            created_by=self.teacher_anand,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/announcements/')
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        ids = [a['id'] for a in results]
        self.assertNotIn(ann_6a.id, ids)

    # 10. Parent cannot access unrelated announcement detail
    def test_10_parent_cannot_access_unrelated_announcement_detail(self):
        ann_6a = Announcement.objects.create(
            school=self.school,
            title="Grade 6-A Parent Teacher Meet",
            content="Meeting on Friday.",
            audience_type=Announcement.AudienceType.CLASS,
            target_class=self.class_6a,
            created_by=self.teacher_anand,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get(f'/api/v1/announcements/{ann_6a.id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    # 11. Teacher can create homework for assigned class
    def test_11_teacher_can_create_homework_for_assigned_class(self):
        self.client.force_authenticate(user=self.teacher_priya)
        payload = {
            'classroom': self.class_5a.id,
            'subject': 'English',
            'title': 'Poem Recitation Preparation',
            'due_date': str(date.today() + timedelta(days=3)),
            'description': 'Read stanza 1 to 3.',
        }
        res = self.client.post('/api/v1/homework/', payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

    # 12. Teacher cannot create homework for unassigned class
    def test_12_teacher_cannot_create_homework_for_unassigned_class(self):
        self.client.force_authenticate(user=self.teacher_priya)
        payload = {
            'classroom': self.class_6a.id,  # Assigned to teacher_anand, NOT priya
            'subject': 'English',
            'title': 'Unauthorized Homework',
            'due_date': str(date.today() + timedelta(days=3)),
        }
        res = self.client.post('/api/v1/homework/', payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    # 13. Teacher can create class announcement for assigned class
    def test_13_teacher_can_create_class_announcement_for_assigned_class(self):
        self.client.force_authenticate(user=self.teacher_priya)
        payload = {
            'audience_type': 'CLASS',
            'target_class': self.class_5a.id,
            'title': 'Maths Test on Monday',
            'content': 'Syllabus: Chapters 1 to 4.',
            'priority': 'IMPORTANT',
        }
        res = self.client.post('/api/v1/announcements/', payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

    # 14. Teacher cannot target unassigned class
    def test_14_teacher_cannot_target_unassigned_class(self):
        self.client.force_authenticate(user=self.teacher_priya)
        payload = {
            'audience_type': 'CLASS',
            'target_class': self.class_6a.id,  # Not assigned to Priya
            'title': 'Unauthorized Circular',
            'content': 'Content',
        }
        res = self.client.post('/api/v1/announcements/', payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    # 15. Homework creation creates parent notifications
    def test_15_homework_creation_creates_parent_notifications(self):
        self.client.force_authenticate(user=self.teacher_priya)
        payload = {
            'classroom': self.class_5a.id,
            'subject': 'Physics',
            'title': 'Optics Laboratory Prep',
            'due_date': str(date.today() + timedelta(days=2)),
        }
        res = self.client.post('/api/v1/homework/', payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

        # Verify notification was generated for Parent Kumar (linked to child in 5-A)
        kumar_notifs = Notification.objects.filter(
            recipient=self.parent_kumar,
            notification_type=Notification.NotificationType.HOMEWORK,
        )
        self.assertTrue(kumar_notifs.exists())
        self.assertIn("Physics", kumar_notifs.first().title)

        # Verify Parent Suresh (whose child is only in 6-A) received NO notification
        suresh_notifs = Notification.objects.filter(
            recipient=self.parent_suresh,
            homework_id=res.data['id'],
        )
        self.assertFalse(suresh_notifs.exists())

    # 16. Announcement creation creates parent notifications
    def test_16_announcement_creation_creates_parent_notifications(self):
        self.client.force_authenticate(user=self.teacher_priya)
        payload = {
            'audience_type': 'CLASS',
            'target_class': self.class_5a.id,
            'title': 'Field Trip Consent Form',
            'content': 'Please submit the consent form tomorrow.',
        }
        res = self.client.post('/api/v1/announcements/', payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

        kumar_notifs = Notification.objects.filter(
            recipient=self.parent_kumar,
            notification_type=Notification.NotificationType.ANNOUNCEMENT,
            announcement_id=res.data['id'],
        )
        self.assertTrue(kumar_notifs.exists())

    # 17. Multiple children supported across different classes
    def test_17_multiple_children_supported_across_different_classes(self):
        # Homework in 5-A
        hw_5a = Homework.objects.create(
            school=self.school,
            classroom=self.class_5a,
            subject="English",
            title="English 5-A",
            due_date=date.today() + timedelta(days=2),
            assigned_by=self.teacher_priya,
        )
        # Homework in 7-B
        hw_7b = Homework.objects.create(
            school=self.school,
            classroom=self.class_7b,
            subject="History",
            title="History 7-B",
            due_date=date.today() + timedelta(days=2),
        )
        # Homework in 6-A (neither child attends)
        hw_6a = Homework.objects.create(
            school=self.school,
            classroom=self.class_6a,
            subject="Maths",
            title="Maths 6-A",
            due_date=date.today() + timedelta(days=2),
            assigned_by=self.teacher_anand,
        )

        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/homework/')
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        hw_ids = [h['id'] for h in results]

        # Must see Grade 5-A and Grade 7-B
        self.assertIn(hw_5a.id, hw_ids)
        self.assertIn(hw_7b.id, hw_ids)
        # Must NOT see Grade 6-A
        self.assertNotIn(hw_6a.id, hw_ids)

    # 18. Duplicate notification is not created for same parent with two children in same class
    def test_18_no_duplicate_notification_when_two_children_in_same_class(self):
        self.client.force_authenticate(user=self.teacher_priya)
        payload = {
            'classroom': self.class_5a.id,
            'subject': 'Art',
            'title': 'Sketching Assignment',
            'due_date': str(date.today() + timedelta(days=4)),
        }
        res = self.client.post('/api/v1/homework/', payload, format='json')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

        # Parent Meena has 2 children in 5-A (Diya & Deepak)
        meena_notifs = Notification.objects.filter(
            recipient=self.parent_meena,
            homework_id=res.data['id'],
        )
        # Exactly 1 notification must be created, not 2!
        self.assertEqual(meena_notifs.count(), 1)

    # 19. Parent can only retrieve own notifications
    def test_19_parent_can_only_retrieve_own_notifications(self):
        notif_kumar = Notification.objects.create(
            recipient=self.parent_kumar,
            notification_type=Notification.NotificationType.HOMEWORK,
            title="Kumar Notif",
            message="Message",
        )
        notif_suresh = Notification.objects.create(
            recipient=self.parent_suresh,
            notification_type=Notification.NotificationType.HOMEWORK,
            title="Suresh Notif",
            message="Message",
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.get('/api/v1/notifications/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        results = res.data if isinstance(res.data, list) else res.data.get('results', [])
        notif_ids = [n['id'] for n in results]
        self.assertIn(notif_kumar.id, notif_ids)
        self.assertNotIn(notif_suresh.id, notif_ids)

    # 20. Parent can mark own notification as read
    def test_20_parent_can_mark_own_notification_as_read(self):
        notif = Notification.objects.create(
            recipient=self.parent_kumar,
            notification_type=Notification.NotificationType.HOMEWORK,
            title="Homework Alert",
            message="Alert message",
            is_read=False,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.patch(f'/api/v1/notifications/{notif.id}/read/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        notif.refresh_from_db()
        self.assertTrue(notif.is_read)

    # 21. Parent cannot mark another user's notification as read
    def test_21_parent_cannot_mark_another_users_notification_as_read(self):
        suresh_notif = Notification.objects.create(
            recipient=self.parent_suresh,
            notification_type=Notification.NotificationType.HOMEWORK,
            title="Suresh Alert",
            message="Secret message",
            is_read=False,
        )
        self.client.force_authenticate(user=self.parent_kumar)
        res = self.client.patch(f'/api/v1/notifications/{suresh_notif.id}/read/')
        # Scoping prevents accessing other users' records
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
        suresh_notif.refresh_from_db()
        self.assertFalse(suresh_notif.is_read)

    # 22. Existing password login still works
    def test_22_password_login_works(self):
        res = self.client.post('/api/v1/auth/login/', {
            'username': 'parent_kumar',
            'password': 'ParentPassword@123',
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('access', res.data)
        self.assertIn('refresh', res.data)

    # 23. Existing Email OTP login still works
    def test_23_email_otp_login_works(self):
        send_res = self.client.post('/api/v1/auth/otp/email/send/', {
            'email': 'kumar.parent@example.com',
        }, format='json')
        self.assertEqual(send_res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 1)

        import re
        otp_match = re.search(r'\b\d{6}\b', mail.outbox[0].body)
        raw_otp = otp_match.group(0)

        verify_res = self.client.post('/api/v1/auth/otp/email/verify/', {
            'email': 'kumar.parent@example.com',
            'otp': raw_otp,
        }, format='json')
        self.assertEqual(verify_res.status_code, status.HTTP_200_OK)
        self.assertIn('access', verify_res.data)

    # 24. JWT refresh still works
    def test_24_jwt_refresh_works(self):
        login_res = self.client.post('/api/v1/auth/login/', {
            'username': 'parent_kumar',
            'password': 'ParentPassword@123',
        }, format='json')
        refresh_token = login_res.data['refresh']

        ref_res = self.client.post('/api/v1/auth/token/refresh/', {
            'refresh': refresh_token,
        }, format='json')
        self.assertEqual(ref_res.status_code, status.HTTP_200_OK)
        self.assertIn('access', ref_res.data)

    # 25. Admin can link parent to student
    def test_25_admin_can_link_parent_to_student(self):
        new_student = Student.objects.create(
            school=self.school,
            admission_number="VIV-999",
            first_name="Varun",
            last_name="Kumar",
            class_enrolled=self.class_5a,
        )
        self.client.force_authenticate(user=self.admin_user)
        res = self.client.post(f'/api/v1/students/{new_student.id}/link-parent/', {
            'parent_id': self.parent_kumar.id,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(new_student.parents.filter(id=self.parent_kumar.id).exists())
