from datetime import date, timedelta
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from rest_framework import status
from rest_framework.test import APITestCase

from apps.schools.models import School
from apps.students.models import (
    Class,
    Student,
    StudentClassEnrollment,
    normalize_academic_year,
    validate_academic_year_format,
)
from apps.homework.models import Homework
from apps.announcements.models import Announcement

User = get_user_model()


class MultiTenantAndFilteringTests(APITestCase):
    """
    Comprehensive verification for:
    1. Strict Multi-Tenant Isolation (School A vs School B)
    2. Zero Cross-Tenant Leakage (List, Detail, Update, Delete, Query Manipulation)
    3. Cross-School Foreign Key Assignment Prevention (HTTP 400)
    4. Academic Year Lifecycle & YYYY-YYYY Validation
    5. Student Class History Tracking (StudentClassEnrollment)
    6. Advanced Multi-Parameter Filtering (Combined, Date Range, Role Scoping)
    """

    def setUp(self):
        # 1. Tenants (Schools)
        self.school_a = School.objects.create(name="St. Xavier's Academy", code="SXA001")
        self.school_b = School.objects.create(name="Delhi Public School", code="DPS002")

        # 2. Users for School A
        self.admin_a = User.objects.create_user(
            username="admin_a", password="Password@123", role=User.Role.ADMIN, school=self.school_a
        )
        self.teacher_a = User.objects.create_user(
            username="teacher_a", password="Password@123", role=User.Role.TEACHER,
            school=self.school_a, first_name="Priya", last_name="Sharma"
        )
        self.parent_a = User.objects.create_user(
            username="parent_a", password="Password@123", role=User.Role.PARENT,
            school=self.school_a, first_name="Ravi", last_name="Kumar"
        )

        # 3. Users for School B
        self.admin_b = User.objects.create_user(
            username="admin_b", password="Password@123", role=User.Role.ADMIN, school=self.school_b
        )
        self.teacher_b = User.objects.create_user(
            username="teacher_b", password="Password@123", role=User.Role.TEACHER,
            school=self.school_b, first_name="Anil", last_name="Verma"
        )
        self.parent_b = User.objects.create_user(
            username="parent_b", password="Password@123", role=User.Role.PARENT,
            school=self.school_b, first_name="Suresh", last_name="Gupta"
        )

        # 4. Classes for School A
        self.class_a_5a = Class.objects.create(
            school=self.school_a, name="Grade 5", section="A", academic_year="2025-2026"
        )
        self.class_a_6a = Class.objects.create(
            school=self.school_a, name="Grade 6", section="A", academic_year="2026-2027"
        )
        self.class_a_8b = Class.objects.create(
            school=self.school_a, name="Grade 8", section="B", academic_year="2025-2026"
        )
        self.class_a_5a.teachers.add(self.teacher_a)

        # 5. Classes for School B
        self.class_b_5a = Class.objects.create(
            school=self.school_b, name="Grade 5", section="A", academic_year="2025-2026"
        )
        self.class_b_5a.teachers.add(self.teacher_b)

        # 6. Students for School A
        self.student_arun = Student.objects.create(
            school=self.school_a, admission_number="ADM-A-001",
            first_name="Arun", last_name="Kumar", class_enrolled=self.class_a_5a
        )
        self.student_arun.parents.add(self.parent_a)

        self.student_diya = Student.objects.create(
            school=self.school_a, admission_number="ADM-A-002",
            first_name="Diya", last_name="Patel", class_enrolled=self.class_a_8b
        )

        # 7. Students for School B
        self.student_ravi = Student.objects.create(
            school=self.school_b, admission_number="ADM-B-001",
            first_name="Ravi", last_name="Gupta", class_enrolled=self.class_b_5a
        )
        self.student_ravi.parents.add(self.parent_b)

        # 8. Homework for School A
        today = date.today()
        self.hw_a_science = Homework.objects.create(
            school=self.school_a, classroom=self.class_a_5a, subject="Science",
            title="Photosynthesis and Plant Cells", description="Draw diagram on page 20.",
            assigned_by=self.teacher_a, assigned_date=today, due_date=today + timedelta(days=3)
        )
        self.hw_a_math = Homework.objects.create(
            school=self.school_a, classroom=self.class_a_5a, subject="Mathematics",
            title="Algebra Basics", description="Solve exercises 1-10.",
            assigned_by=self.teacher_a, assigned_date=today, due_date=today + timedelta(days=5)
        )
        self.hw_a_grade8 = Homework.objects.create(
            school=self.school_a, classroom=self.class_a_8b, subject="History",
            title="World War II Timeline", description="Create timeline chart.",
            assigned_by=self.teacher_a, assigned_date=today, due_date=today + timedelta(days=7)
        )

        # 9. Homework for School B
        self.hw_b_science = Homework.objects.create(
            school=self.school_b, classroom=self.class_b_5a, subject="Science",
            title="Solar System & Planets", description="Read chapter 4.",
            assigned_by=self.teacher_b, assigned_date=today, due_date=today + timedelta(days=3)
        )

        # 10. Announcements for School A
        self.ann_a_school = Announcement.objects.create(
            school=self.school_a, title="School A Annual Sports Meet",
            content="Sports meet on Sept 20.", priority=Announcement.Priority.URGENT,
            audience_type=Announcement.AudienceType.SCHOOL, created_by=self.admin_a
        )
        self.ann_a_class = Announcement.objects.create(
            school=self.school_a, title="Grade 5-A Field Trip",
            content="Field trip permission slip due tomorrow.",
            priority=Announcement.Priority.NORMAL,
            audience_type=Announcement.AudienceType.CLASS,
            target_class=self.class_a_5a, created_by=self.teacher_a
        )

        # 11. Announcements for School B
        self.ann_b_school = Announcement.objects.create(
            school=self.school_b, title="School B Science Exhibition",
            content="Exhibition on Oct 15.", priority=Announcement.Priority.IMPORTANT,
            audience_type=Announcement.AudienceType.SCHOOL, created_by=self.admin_b
        )

    # =========================================================================
    # 1. MULTI-TENANT ISOLATION TESTS
    # =========================================================================

    def test_admin_a_cannot_list_school_b_data(self):
        """Admin A querying list endpoints receives ONLY School A records."""
        self.client.force_authenticate(user=self.admin_a)

        # Classes
        res = self.client.get('/api/v1/classes/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        class_ids = [c['id'] for c in res.data['results']]
        self.assertIn(self.class_a_5a.id, class_ids)
        self.assertNotIn(self.class_b_5a.id, class_ids)

        # Students
        res = self.client.get('/api/v1/students/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        student_ids = [s['id'] for s in res.data['results']]
        self.assertIn(self.student_arun.id, student_ids)
        self.assertNotIn(self.student_ravi.id, student_ids)

        # Homework
        res = self.client.get('/api/v1/homework/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        hw_ids = [h['id'] for h in res.data['results']]
        self.assertIn(self.hw_a_science.id, hw_ids)
        self.assertNotIn(self.hw_b_science.id, hw_ids)

        # Announcements
        res = self.client.get('/api/v1/announcements/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        ann_ids = [a['id'] for a in res.data['results']]
        self.assertIn(self.ann_a_school.id, ann_ids)
        self.assertNotIn(self.ann_b_school.id, ann_ids)

    def test_teacher_a_cannot_access_school_b_detail(self):
        """Teacher A querying School B objects via direct ID receives 404."""
        self.client.force_authenticate(user=self.teacher_a)

        # School B class detail -> 404
        res = self.client.get(f'/api/v1/classes/{self.class_b_5a.id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

        # School B student detail -> 404
        res = self.client.get(f'/api/v1/students/{self.student_ravi.id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

        # School B homework detail -> 404
        res = self.client.get(f'/api/v1/homework/{self.hw_b_science.id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

        # School B announcement detail -> 404
        res = self.client.get(f'/api/v1/announcements/{self.ann_b_school.id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_user_a_cannot_modify_or_delete_school_b_data(self):
        """Users from School A cannot update or delete School B records."""
        self.client.force_authenticate(user=self.admin_a)

        # Attempt PATCH on School B class
        res = self.client.patch(f'/api/v1/classes/{self.class_b_5a.id}/', {'name': 'Hacked Class'})
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

        # Attempt DELETE on School B homework
        res = self.client.delete(f'/api/v1/homework/{self.hw_b_science.id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

        # Verify DB unchanged
        self.class_b_5a.refresh_from_db()
        self.assertEqual(self.class_b_5a.name, "Grade 5")
        self.assertTrue(Homework.objects.filter(id=self.hw_b_science.id).exists())

    def test_parent_b_cannot_access_school_a_data(self):
        """Parent B cannot see any data from School A."""
        self.client.force_authenticate(user=self.parent_b)

        # Homework: Parent B only sees their child's class in School B
        res = self.client.get('/api/v1/homework/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        hw_ids = [h['id'] for h in res.data['results']]
        self.assertIn(self.hw_b_science.id, hw_ids)
        self.assertNotIn(self.hw_a_science.id, hw_ids)

        # Announcements: Parent B only sees School B announcements
        res = self.client.get('/api/v1/announcements/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        ann_ids = [a['id'] for a in res.data['results']]
        self.assertIn(self.ann_b_school.id, ann_ids)
        self.assertNotIn(self.ann_a_school.id, ann_ids)

    # =========================================================================
    # 2. CROSS-SCHOOL FOREIGN KEY ATTEMPT REJECTION (HTTP 400)
    # =========================================================================

    def test_cannot_assign_homework_to_another_schools_class(self):
        """Teacher A cannot create homework targeting School B's class."""
        self.client.force_authenticate(user=self.teacher_a)
        res = self.client.post('/api/v1/homework/', {
            'classroom': self.class_b_5a.id,
            'subject': 'Physics',
            'title': 'Cross School Homework Attempt',
            'due_date': str(date.today() + timedelta(days=2)),
        })
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('classroom', res.data)

    def test_cannot_enroll_student_in_another_schools_class(self):
        """Admin A cannot enroll a student in School B's class."""
        self.client.force_authenticate(user=self.admin_a)
        res = self.client.post('/api/v1/students/', {
            'admission_number': 'HACK-001',
            'first_name': 'Trojan',
            'class_enrolled': self.class_b_5a.id,
        })
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('class_enrolled', res.data)

    def test_cannot_link_parent_from_another_school(self):
        """Admin A cannot associate School B's parent to a School A student."""
        self.client.force_authenticate(user=self.admin_a)
        res = self.client.post('/api/v1/students/', {
            'admission_number': 'STU-CROSS-01',
            'first_name': 'Meera',
            'class_enrolled': self.class_a_5a.id,
            'parents': [self.parent_b.id],
        })
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('parents', res.data)

    def test_cannot_assign_teacher_from_another_school_to_class(self):
        """Admin A cannot assign Teacher B to School A's class."""
        self.client.force_authenticate(user=self.admin_a)
        res = self.client.post('/api/v1/classes/', {
            'name': 'Grade 9',
            'section': 'C',
            'academic_year': '2025-2026',
            'teachers': [self.teacher_b.id],
        })
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('teachers', res.data)

    def test_cannot_target_announcement_to_another_schools_class(self):
        """Admin A cannot create a class announcement targeting School B's class."""
        self.client.force_authenticate(user=self.admin_a)
        res = self.client.post('/api/v1/announcements/', {
            'title': 'Cross-School Circular',
            'content': 'Attempting cross-tenant targeting',
            'audience_type': 'CLASS',
            'target_class': self.class_b_5a.id,
        })
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('target_class', res.data)

    # =========================================================================
    # 3. QUERY PARAMETER MANIPULATION (IDOR RESISTANCE)
    # =========================================================================

    def test_query_parameter_foreign_class_returns_empty(self):
        """School A user passing ?class_id=<School B class> gets NO School B data."""
        self.client.force_authenticate(user=self.teacher_a)

        # Homework query
        res = self.client.get(f'/api/v1/homework/?class_id={self.class_b_5a.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['results']), 0)

        # Students query
        res = self.client.get(f'/api/v1/students/?class_id={self.class_b_5a.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['results']), 0)

        # Announcements query
        res = self.client.get(f'/api/v1/announcements/?class_id={self.class_b_5a.id}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['results']), 0)

    # =========================================================================
    # 4. ACADEMIC YEAR (YYYY-YYYY) VALIDATION & LIFECYCLE
    # =========================================================================

    def test_academic_year_yyyy_yyyy_standardization(self):
        """Academic year must strictly adhere to YYYY-YYYY format."""
        self.client.force_authenticate(user=self.admin_a)

        # Valid consecutive format: 2025-2026
        res = self.client.post('/api/v1/classes/', {
            'name': 'Grade 1',
            'section': 'A',
            'academic_year': '2025-2026',
        })
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['academic_year'], '2025-2026')

        # Normalization: short format '2027-28' is converted to '2027-2028'
        res = self.client.post('/api/v1/classes/', {
            'name': 'Grade 2',
            'section': 'A',
            'academic_year': '2027-28',
        })
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['academic_year'], '2027-2028')

        # Invalid format: non-consecutive years (2025-2027) rejected
        res = self.client.post('/api/v1/classes/', {
            'name': 'Grade 3',
            'section': 'A',
            'academic_year': '2025-2027',
        })
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    # =========================================================================
    # 5. STUDENT CLASS HISTORY TRACKING (StudentClassEnrollment)
    # =========================================================================

    def test_student_class_history_across_academic_years(self):
        """
        Tests student historical enrollment lifecycle:
        2025-2026: Grade 5-A
        2026-2027: Promoted to Grade 6-A
        Both enrollment records must remain queryable without loss.
        """
        self.client.force_authenticate(user=self.admin_a)

        # Initial enrollment (2025-2026) verified from setUp
        self.assertEqual(self.student_arun.enrollments.count(), 1)
        initial_enrollment = self.student_arun.enrollments.first()
        self.assertEqual(initial_enrollment.academic_year, '2025-2026')
        self.assertEqual(initial_enrollment.classroom, self.class_a_5a)
        self.assertTrue(initial_enrollment.is_current)

        # Promote student to Grade 6-A (2026-2027) via enrollments endpoint
        res = self.client.post(f'/api/v1/students/{self.student_arun.id}/enrollments/', {
            'classroom': self.class_a_6a.id,
            'academic_year': '2026-2027',
        })
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)

        # Verify DB records
        self.student_arun.refresh_from_db()
        self.assertEqual(self.student_arun.class_enrolled, self.class_a_6a)
        self.assertEqual(self.student_arun.enrollments.count(), 2)

        # GET /api/v1/students/<id>/enrollments/
        res = self.client.get(f'/api/v1/students/{self.student_arun.id}/enrollments/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        years = [e['academic_year'] for e in res.data]
        self.assertIn('2025-2026', years)
        self.assertIn('2026-2027', years)

        # Filtering student by historical academic year
        res_hist = self.client.get('/api/v1/students/?academic_year=2025-2026')
        self.assertEqual(res_hist.status_code, status.HTTP_200_OK)
        student_ids = [s['id'] for s in res_hist.data['results']]
        self.assertIn(self.student_arun.id, student_ids)

        # Filtering student by new academic year
        res_new = self.client.get('/api/v1/students/?academic_year=2026-2027')
        self.assertEqual(res_new.status_code, status.HTTP_200_OK)
        student_ids = [s['id'] for s in res_new.data['results']]
        self.assertIn(self.student_arun.id, student_ids)

    # =========================================================================
    # 6. ADVANCED FILTERING TESTS
    # =========================================================================

    def test_combined_homework_filters(self):
        """Tests multi-parameter filtering: academic_year + class_id + subject."""
        self.client.force_authenticate(user=self.admin_a)

        # 2025-2026 + Class 5-A + Science
        res = self.client.get(
            f'/api/v1/homework/?academic_year=2025-2026&class_id={self.class_a_5a.id}&subject=Science'
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['results']), 1)
        self.assertEqual(res.data['results'][0]['id'], self.hw_a_science.id)

        # Also support short notation '2025-26'
        res_short = self.client.get(
            f'/api/v1/homework/?academic_year=2025-26&class_id={self.class_a_5a.id}&subject=Science'
        )
        self.assertEqual(res_short.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res_short.data['results']), 1)

    def test_homework_filtered_by_student(self):
        """Tests ?student=Arun returns homework for Arun's enrolled class."""
        self.client.force_authenticate(user=self.admin_a)
        res = self.client.get('/api/v1/homework/?student=Arun')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        hw_ids = [h['id'] for h in res.data['results']]
        self.assertIn(self.hw_a_science.id, hw_ids)
        self.assertIn(self.hw_a_math.id, hw_ids)
        self.assertNotIn(self.hw_a_grade8.id, hw_ids)  # Grade 8 is not Arun's class

    def test_homework_date_range_filtering(self):
        """Tests date range filtering on homework assigned_date."""
        self.client.force_authenticate(user=self.admin_a)
        today = date.today()
        from_str = str(today - timedelta(days=1))
        to_str = str(today + timedelta(days=1))

        res = self.client.get(f'/api/v1/homework/?from_date={from_str}&to_date={to_str}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['results']), 3)

        # Out of bounds date range
        res_empty = self.client.get('/api/v1/homework/?from_date=2020-01-01&to_date=2020-01-02')
        self.assertEqual(res_empty.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res_empty.data['results']), 0)

    def test_announcement_filtering(self):
        """Tests announcement filtering by priority, academic_year, and audience_type."""
        self.client.force_authenticate(user=self.admin_a)

        # Priority = URGENT
        res = self.client.get('/api/v1/announcements/?priority=URGENT')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['results']), 1)
        self.assertEqual(res.data['results'][0]['id'], self.ann_a_school.id)

        # Academic Year = 2025-2026 (includes school-wide + class matching 2025-2026)
        res_year = self.client.get('/api/v1/announcements/?academic_year=2025-2026')
        self.assertEqual(res_year.status_code, status.HTTP_200_OK)
        ann_ids = [a['id'] for a in res_year.data['results']]
        self.assertIn(self.ann_a_school.id, ann_ids)
        self.assertIn(self.ann_a_class.id, ann_ids)

    def test_student_name_search(self):
        """Tests student search by first_name, last_name, or admission number."""
        self.client.force_authenticate(user=self.admin_a)

        # By first name
        res = self.client.get('/api/v1/students/?name=Arun')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data['results']), 1)
        self.assertEqual(res.data['results'][0]['id'], self.student_arun.id)

        # By admission number
        res_adm = self.client.get('/api/v1/students/?admission_number=ADM-A-002')
        self.assertEqual(res_adm.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res_adm.data['results']), 1)
        self.assertEqual(res_adm.data['results'][0]['id'], self.student_diya.id)

    def test_parent_scoping_sees_only_own_children(self):
        """Parent A only sees student Arun, never Diya or School B students."""
        self.client.force_authenticate(user=self.parent_a)

        res = self.client.get('/api/v1/students/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        student_ids = [s['id'] for s in res.data['results']]
        self.assertIn(self.student_arun.id, student_ids)
        self.assertNotIn(self.student_diya.id, student_ids)
        self.assertNotIn(self.student_ravi.id, student_ids)
