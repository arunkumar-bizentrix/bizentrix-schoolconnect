"""
Scale checks for a real school roll.

A single school here is expected to carry 1000+ students. These tests build
that roll in the throwaway test database and assert two things that only bite
at size:

1. Query count stays flat as the roll grows - no N+1 walk over students,
   classes, parents or teachers.
2. The list endpoints stay paginated and searchable, so a client can page
   through the roll instead of trying to hold it all in memory.
"""

import time

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.homework.models import Homework
from apps.schools.models import School
from apps.students.models import Class, Student

User = get_user_model()

ROLL_SIZE = 1000
ACADEMIC_YEAR = '2026-2027'


class LargeRollPerformanceTests(TestCase):
    """One school, 1000 students across 25 classes, with parents attached."""

    @classmethod
    def setUpTestData(cls):
        cls.school = School.objects.create(name="Scale Test School", code="SCL01")

        cls.admin = User.objects.create_user(
            username='scale_admin', password='Password@123',
            role=User.Role.ADMIN, school=cls.school,
        )
        cls.teacher = User.objects.create_user(
            username='scale_teacher', password='Password@123',
            role=User.Role.TEACHER, school=cls.school,
        )

        cls.classes = [
            Class.objects.create(
                school=cls.school,
                name=f'Grade {(index % 12) + 1}',
                section=chr(ord('A') + (index // 12)),
                academic_year=ACADEMIC_YEAR,
            )
            for index in range(25)
        ]
        for classroom in cls.classes[:5]:
            classroom.teachers.add(cls.teacher)

        Student.objects.bulk_create([
            Student(
                school=cls.school,
                admission_number=f'ADM{index:05d}',
                first_name=f'Student{index}',
                last_name=f'Family{index % 97}',
                class_enrolled=cls.classes[index % 25],
                is_active=True,
            )
            for index in range(ROLL_SIZE)
        ])

        # A parent for every 20th student, each with two children, so the
        # parent-scoped queries have realistic fan-out too.
        cls.parents = [
            User.objects.create_user(
                username=f'scale_parent_{index}', password='Password@123',
                role=User.Role.PARENT, school=cls.school,
            )
            for index in range(50)
        ]
        students = list(Student.objects.filter(school=cls.school).order_by('id'))
        for index, parent in enumerate(cls.parents):
            students[index * 2].parents.add(parent)
            students[index * 2 + 1].parents.add(parent)

        Homework.objects.bulk_create([
            Homework(
                school=cls.school,
                classroom=cls.classes[index % 25],
                subject='Mathematics',
                title=f'Worksheet {index}',
                assigned_by=cls.teacher,
                due_date='2026-12-31',
            )
            for index in range(200)
        ])

    def setUp(self):
        self.client = APIClient()

    # ------------------------------------------------------------------
    # pagination
    # ------------------------------------------------------------------

    def test_student_list_is_paginated_not_truncated_silently(self):
        """
        The roll must come back paged, with a total count and a next link, so a
        client knows there is more. A client that ignores `next` sees only the
        first page - that is a client bug, and this pins the contract it relies on.
        """
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/v1/students/')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], ROLL_SIZE)
        self.assertEqual(len(response.data['results']), 20)
        self.assertIsNotNone(
            response.data['next'],
            'a 1000-student roll must advertise a next page',
        )

    def test_every_student_is_reachable_by_paging(self):
        self.client.force_authenticate(user=self.admin)

        seen = 0
        url = '/api/v1/students/?page_size=100'
        pages = 0
        while url and pages < 60:
            response = self.client.get(url)
            self.assertEqual(response.status_code, status.HTTP_200_OK)
            seen += len(response.data['results'])
            url = response.data['next']
            pages += 1

        self.assertEqual(seen, ROLL_SIZE)

    # ------------------------------------------------------------------
    # query count - the thing that actually degrades with size
    # ------------------------------------------------------------------

    def test_student_page_query_count_is_flat(self):
        """Serializing a page must not walk related rows one at a time."""
        self.client.force_authenticate(user=self.admin)
        # count + page + parents prefetch + enrollments prefetch. Flat: the
        # same 4 whether the roll is 14 students or 1000.
        with self.assertNumQueries(4):
            response = self.client.get('/api/v1/students/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_class_list_query_count_is_flat(self):
        """
        student_count is annotated, so 25 classes must not cost 25 extra
        COUNT queries.
        """
        self.client.force_authenticate(user=self.admin)
        # count + page (with the student_count annotation) + teachers prefetch.
        with self.assertNumQueries(3):
            response = self.client.get(f'/api/v1/classes/?academic_year={ACADEMIC_YEAR}')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_homework_page_query_count_is_flat(self):
        self.client.force_authenticate(user=self.teacher)
        # count + page; every relation the serializer touches is select_related.
        with self.assertNumQueries(2):
            response = self.client.get('/api/v1/homework/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # search - the only workable way to find one child in a roll of 1000
    # ------------------------------------------------------------------

    def test_search_narrows_the_roll_server_side(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/v1/students/?search=ADM00042')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['admission_number'], 'ADM00042')

    def test_search_by_name_narrows_the_roll(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/v1/students/?search=Student777')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(response.data['count'], 1)
        self.assertTrue(
            all('Student777' in row['first_name'] for row in response.data['results'])
        )

    def test_class_filter_narrows_the_roll(self):
        self.client.force_authenticate(user=self.admin)
        classroom = self.classes[0]
        response = self.client.get(f'/api/v1/students/?class_id={classroom.id}')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], ROLL_SIZE // 25)

    # ------------------------------------------------------------------
    # role scoping still holds at size
    # ------------------------------------------------------------------

    def test_teacher_sees_only_their_classes_students_at_scale(self):
        self.client.force_authenticate(user=self.teacher)
        response = self.client.get('/api/v1/students/')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        # 5 assigned classes out of 25
        self.assertEqual(response.data['count'], ROLL_SIZE // 5)

    def test_parent_sees_only_their_own_children_at_scale(self):
        self.client.force_authenticate(user=self.parents[0])
        response = self.client.get('/api/v1/students/')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 2)

    # ------------------------------------------------------------------
    # wall clock - a rough guard, generous enough not to be flaky
    # ------------------------------------------------------------------

    def test_student_page_responds_quickly(self):
        self.client.force_authenticate(user=self.admin)

        started = time.perf_counter()
        response = self.client.get('/api/v1/students/')
        elapsed = time.perf_counter() - started

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertLess(
            elapsed, 1.5,
            f'one page of a {ROLL_SIZE}-student roll took {elapsed:.2f}s',
        )
