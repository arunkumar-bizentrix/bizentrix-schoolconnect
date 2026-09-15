"""
Walking every page of /classes/ must return each class exactly once.

Pickers (attendance, timetable, homework) load all of a user's classes, and a
school has more than one page of them.
"""

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.schools.models import School
from apps.students.models import Class

User = get_user_model()


class ClassPaginationTests(APITestCase):
    YEAR = '2026-2027'

    def setUp(self):
        self.school = School.objects.create(name='Paging School', code='PGS01')
        self.admin = User.objects.create_user(
            username='pg_admin', password='x', role=User.Role.ADMIN, school=self.school,
        )
        self.teacher = User.objects.create_user(
            username='pg_teacher', password='x', role=User.Role.TEACHER, school=self.school,
        )
        self.parent = User.objects.create_user(
            username='pg_parent', password='x', role=User.Role.PARENT, school=self.school,
        )

        # 25 classes this year. Many share a name and section with a class of
        # another year - exactly the ties that made paging unstable.
        self.classes = []
        for grade in range(1, 14):
            for section in ('A', 'B'):
                if len(self.classes) == 25:
                    break
                self.classes.append(Class.objects.create(
                    school=self.school, name=f'Grade {grade}', section=section,
                    academic_year=self.YEAR,
                ))
        for grade in range(1, 6):
            Class.objects.create(
                school=self.school, name=f'Grade {grade}', section='A',
                academic_year='2025-2026',
            )

        self.assigned = self.classes[3:6]
        for classroom in self.assigned:
            classroom.teachers.add(self.teacher)

    def walk(self, user, query=''):
        self.client.force_authenticate(user=user)
        url = f'/api/v1/classes/?academic_year={self.YEAR}{query}'
        ids, pages = [], 0
        while url:
            res = self.client.get(url)
            self.assertEqual(res.status_code, status.HTTP_200_OK)
            ids.extend(row['id'] for row in res.data['results'])
            url = res.data['next']
            pages += 1
            self.assertLess(pages, 10, 'paging never ended')
        return ids, pages

    def test_admin_gets_all_25_classes_across_pages_without_duplicates(self):
        ids, pages = self.walk(self.admin)
        self.assertEqual(pages, 2)
        self.assertEqual(len(ids), 25)
        self.assertEqual(len(set(ids)), 25, 'a class appeared on two pages')
        self.assertEqual(set(ids), {c.id for c in self.classes})

    def test_first_page_reports_the_full_count(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.get(f'/api/v1/classes/?academic_year={self.YEAR}')
        self.assertEqual(res.data['count'], 25)
        self.assertEqual(len(res.data['results']), 20)
        self.assertIsNotNone(res.data['next'])

    def test_every_year_together_is_still_duplicate_free(self):
        self.client.force_authenticate(user=self.admin)
        url, ids = '/api/v1/classes/', []
        while url:
            res = self.client.get(url)
            ids.extend(row['id'] for row in res.data['results'])
            url = res.data['next']
        self.assertEqual(len(ids), 30)
        self.assertEqual(len(set(ids)), 30)

    def test_client_ordering_keeps_pages_stable(self):
        ids, _ = self.walk(self.admin, '&ordering=section')
        self.assertEqual(len(ids), 25)
        self.assertEqual(len(set(ids)), 25)

    def test_teacher_receives_only_assigned_classes(self):
        ids, pages = self.walk(self.teacher)
        self.assertEqual(pages, 1)
        self.assertEqual(sorted(ids), sorted(c.id for c in self.assigned))

    def test_teacher_cannot_open_an_unassigned_class(self):
        self.client.force_authenticate(user=self.teacher)
        res = self.client.get(f'/api/v1/classes/{self.classes[0].id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_search_still_works_across_all_classes(self):
        ids, _ = self.walk(self.admin, '&search=Grade 12')
        self.assertEqual(len(ids), 2)

    def test_parent_lists_only_their_childrens_classes(self):
        from apps.students.models import Student
        child = Student.objects.create(
            school=self.school, admission_number='PG-1', first_name='Kavya',
            class_enrolled=self.classes[10],
        )
        child.parents.add(self.parent)
        sibling = Student.objects.create(
            school=self.school, admission_number='PG-2', first_name='Diya',
            class_enrolled=self.classes[10],
        )
        sibling.parents.add(self.parent)

        ids, _ = self.walk(self.parent)
        self.assertEqual(ids, [self.classes[10].id])

        self.client.force_authenticate(user=self.parent)
        other = self.client.get(f'/api/v1/classes/{self.classes[0].id}/')
        self.assertEqual(other.status_code, status.HTTP_404_NOT_FOUND)
        own = self.client.get(f'/api/v1/classes/{self.classes[10].id}/')
        self.assertEqual(own.data['student_count'], 2, 'count must not be multiplied by the parent join')

    def test_parent_cannot_manage_classes(self):
        self.client.force_authenticate(user=self.parent)
        res = self.client.post('/api/v1/classes/', {
            'name': 'Grade 99', 'section': 'Z', 'academic_year': self.YEAR,
        }, format='json')
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        res = self.client.delete(f'/api/v1/classes/{self.classes[0].id}/')
        self.assertIn(res.status_code, (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND))
        self.assertTrue(Class.objects.filter(id=self.classes[0].id).exists())
