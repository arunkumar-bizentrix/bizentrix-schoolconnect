"""
Seeds academic demo data for local manual testing.

Companion to `seed_demo_users`, which only creates the user accounts. This
command wires up the records those users need in order to see anything:
a class for the current academic year, students, a parent-child link,
homework, announcements and the notifications they generate.

Idempotent: safe to run repeatedly. It only ever creates missing rows or
attaches missing links - it never deletes or resets anything.

    python manage.py seed_demo_data

Development only. The demo accounts use well-known local passwords and must
never exist in a production database.
"""

from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.accounts.models import User
from apps.announcements.models import Announcement
from apps.exams.models import Exam, ExamPaper, Mark
from apps.exams.services import publish_exam
from apps.homework.models import Homework
from apps.notifications.services import NotificationService
from apps.schools.services import get_default_school
from apps.students.models import Class, Student
from apps.timetable.models import Subject, TimetableSlot

# Must match AppConstants.currentAcademicYear in the Flutter app, otherwise
# the app's list queries filter out everything this command creates.
ACADEMIC_YEAR = '2026-2027'


class Command(BaseCommand):
    help = 'Seeds classes, students, parent links, homework and announcements for manual testing'

    def handle(self, *args, **options):
        school = get_default_school()
        if school is None:
            self.stderr.write(self.style.ERROR(
                'No School row found. Run `python manage.py seed_demo_users` first.'
            ))
            return

        self.stdout.write(self.style.MIGRATE_HEADING(f'School: {school}'))

        teacher = User.objects.filter(username='teacher_priya').first()
        parent = User.objects.filter(username='parent_ravi').first()
        if not teacher or not parent:
            self.stderr.write(self.style.ERROR(
                'Demo users missing. Run `python manage.py seed_demo_users` first.'
            ))
            return

        # ------------------------------------------------------------------
        # Classes for the current academic year
        # ------------------------------------------------------------------
        class_5a, _ = Class.objects.get_or_create(
            school=school, name='Grade 5', section='A', academic_year=ACADEMIC_YEAR,
            defaults={'is_active': True},
        )
        class_6b, _ = Class.objects.get_or_create(
            school=school, name='Grade 6', section='B', academic_year=ACADEMIC_YEAR,
            defaults={'is_active': True},
        )
        # Teacher is assigned to 5-A only, so "assigned classes" scoping is visible.
        class_5a.teachers.add(teacher)
        class_6b.teachers.remove(teacher)
        # ...and is its class teacher, so she takes its attendance.
        if class_5a.class_teacher_id != teacher.id:
            class_5a.class_teacher = teacher
            class_5a.save(update_fields=['class_teacher'])
        self.stdout.write(self.style.SUCCESS(
            f'Classes ready: {class_5a} (teacher_priya assigned), {class_6b} (unassigned)'
        ))

        # ------------------------------------------------------------------
        # Students
        # ------------------------------------------------------------------
        students = {}
        for adm, first, last, classroom in [
            ('ABC-5A-01', 'Kavya', 'Sundaram', class_5a),
            ('ABC-5A-02', 'Rahul', 'Murugan', class_5a),
            ('ABC-6B-01', 'Ananya', 'Krishnan', class_6b),
        ]:
            student, _ = Student.objects.get_or_create(
                school=school, admission_number=adm,
                defaults={'first_name': first, 'last_name': last, 'is_active': True},
            )
            if student.class_enrolled_id != classroom.id:
                student.class_enrolled = classroom
                student.save()
            students[adm] = student

        # The pre-existing demo child had no class, so the parent dashboard was
        # empty. Put them in 5-A alongside the others.
        aarav = Student.objects.filter(school=school, admission_number='ADM001').first()
        if aarav and aarav.class_enrolled_id != class_5a.id:
            aarav.class_enrolled = class_5a
            aarav.save()
        if aarav:
            students['ADM001'] = aarav

        self.stdout.write(self.style.SUCCESS(
            'Students ready: ' + ', '.join(
                f'{s.full_name} -> {s.class_enrolled}' for s in students.values()
            )
        ))

        # ------------------------------------------------------------------
        # Parent - child links
        #
        # Modelled on real families, not on showing off the switcher: a parent
        # sees their own children and nobody else's. Ravi Kumar has two
        # children in different classes, which is what the child switcher is
        # for; the other two children have their own parent.
        # ------------------------------------------------------------------
        diya, _ = Student.objects.get_or_create(
            school=school, admission_number='ADM-KUMAR-02',
            defaults={
                'first_name': 'Diya',
                'last_name': 'Kumar',
                'is_active': True,
            },
        )
        if diya.class_enrolled_id != class_6b.id:
            diya.class_enrolled = class_6b
            diya.save()
        students['ADM-KUMAR-02'] = diya

        def demo_parent(username, first_name, last_name, phone):
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    'first_name': first_name,
                    'last_name': last_name,
                    'role': User.Role.PARENT,
                    'school': school,
                    'phone_number': phone,
                    'is_active': True,
                },
            )
            if created:
                user.set_password('Parent@123')
                user.save()
            return user

        sundaram = demo_parent('parent_sundaram', 'Meena', 'Sundaram', '9000000101')
        krishnan = demo_parent('parent_krishnan', 'Latha', 'Krishnan', '9000000102')

        # set() rather than add(): re-running fixes a wrong link instead of
        # piling another one on top.
        family = {
            'ADM001': parent,            # Aarav Kumar   -> Ravi Kumar
            'ADM-KUMAR-02': parent,      # Diya Kumar    -> Ravi Kumar (sibling)
            'ABC-5A-01': sundaram,       # Kavya Sundaram
            'ABC-6B-01': krishnan,       # Ananya Krishnan
        }
        for admission_number, guardian in family.items():
            student = students.get(admission_number)
            if student:
                student.parents.set([guardian])

        self.stdout.write(self.style.SUCCESS(
            'Parent links: '
            + '; '.join(
                f"{guardian.username} -> "
                f"{', '.join(guardian.children.values_list('first_name', flat=True))}"
                for guardian in {parent, sundaram, krishnan}
            )
        ))

        # ------------------------------------------------------------------
        # Homework (future due dates so nothing shows as overdue)
        # ------------------------------------------------------------------
        today = timezone.localdate()
        homework_rows = [
            (class_5a, 'Mathematics', 'Fractions worksheet',
             'Complete exercises 4.1 to 4.4 in the workbook.', 3),
            (class_5a, 'Science', 'Plant life cycle diagram',
             'Draw and label the stages of a flowering plant life cycle.', 5),
            (class_6b, 'English', 'Book review',
             'Write a one-page review of the class reader.', 4),
        ]
        created_homework = []
        for classroom, subject, title, description, due_in_days in homework_rows:
            homework, created = Homework.objects.get_or_create(
                school=school, classroom=classroom, subject=subject, title=title,
                defaults={
                    'description': description,
                    'assigned_by': teacher,
                    'assigned_date': today,
                    'due_date': today + timedelta(days=due_in_days),
                    'is_active': True,
                },
            )
            if created:
                created_homework.append(homework)
        self.stdout.write(self.style.SUCCESS(
            f'Homework ready: {Homework.objects.filter(classroom__academic_year=ACADEMIC_YEAR).count()} '
            f'items for {ACADEMIC_YEAR} ({len(created_homework)} new)'
        ))

        # ------------------------------------------------------------------
        # Announcements
        # ------------------------------------------------------------------
        created_announcements = []
        school_notice, created = Announcement.objects.get_or_create(
            school=school,
            title='Annual Sports Day',
            audience_type=Announcement.AudienceType.SCHOOL,
            defaults={
                'content': (
                    'Annual Sports Day will be held on the school ground. '
                    'All students should report by 8:00 AM in sports uniform.'
                ),
                'priority': Announcement.Priority.IMPORTANT,
                'created_by': User.objects.filter(username='admin').first(),
                'published_at': timezone.now(),
                'is_active': True,
            },
        )
        if created:
            created_announcements.append(school_notice)

        class_notice, created = Announcement.objects.get_or_create(
            school=school,
            title='Grade 5-A field trip consent',
            audience_type=Announcement.AudienceType.CLASS,
            target_class=class_5a,
            defaults={
                'content': 'Please return the signed consent form before Friday.',
                'priority': Announcement.Priority.NORMAL,
                'created_by': teacher,
                'published_at': timezone.now(),
                'is_active': True,
            },
        )
        if created:
            created_announcements.append(class_notice)

        urgent_notice, created = Announcement.objects.get_or_create(
            school=school,
            title='Early dismissal tomorrow',
            audience_type=Announcement.AudienceType.SCHOOL,
            defaults={
                'content': 'School will close at 12:30 PM tomorrow due to staff training.',
                'priority': Announcement.Priority.URGENT,
                'created_by': User.objects.filter(username='admin').first(),
                'published_at': timezone.now(),
                'is_active': True,
            },
        )
        if created:
            created_announcements.append(urgent_notice)

        self.stdout.write(self.style.SUCCESS(
            f'Announcements ready: {Announcement.objects.filter(school=school).count()} total '
            f'({len(created_announcements)} new)'
        ))

        # ------------------------------------------------------------------
        # Notifications - generated the same way the API generates them
        # ------------------------------------------------------------------
        for homework in created_homework:
            NotificationService.create_homework_notifications(homework)
        for announcement in created_announcements:
            NotificationService.create_announcement_notifications(announcement)

        notif_count = parent.notifications.count()
        if notif_count == 0:
            # Everything already existed, so nothing new fanned out. Generate
            # notifications for the current records so the bell is not empty.
            for homework in Homework.objects.filter(classroom=class_5a, is_active=True):
                NotificationService.create_homework_notifications(homework)
            for announcement in [school_notice, class_notice, urgent_notice]:
                NotificationService.create_announcement_notifications(announcement)
            notif_count = parent.notifications.count()

        self.stdout.write(self.style.SUCCESS(
            f'Notifications for parent_ravi: {notif_count}'
        ))

        # ------------------------------------------------------------------
        # A week of periods for Grade 5-A, so the timetable screens have
        # something real to draw. Monday to Friday, five periods a day.
        # ------------------------------------------------------------------
        subject_names = ['Mathematics', 'English', 'Science', 'Social Science', 'Tamil']
        subjects = []
        for name in subject_names:
            subject, _ = Subject.objects.get_or_create(
                school=school, name=name, defaults={'is_active': True}
            )
            subjects.append(subject)

        period_times = [
            ('09:00', '09:45'),
            ('09:45', '10:30'),
            ('11:00', '11:45'),
            ('11:45', '12:30'),
            ('13:30', '14:15'),
        ]

        slots_created = 0
        for weekday in range(5):  # Monday to Friday
            for index, (start, end) in enumerate(period_times, start=1):
                # Rotate subjects so no day looks like a copy of the last.
                subject = subjects[(weekday + index) % len(subjects)]
                _, created = TimetableSlot.objects.get_or_create(
                    classroom=class_5a,
                    weekday=weekday,
                    period=index,
                    defaults={
                        'school': school,
                        'subject': subject,
                        'teacher': teacher,
                        'start_time': start,
                        'end_time': end,
                    },
                )
                if created:
                    slots_created += 1

        self.stdout.write(self.style.SUCCESS(
            f'Timetable ready: {TimetableSlot.objects.filter(classroom=class_5a).count()} '
            f'periods for {class_5a} ({slots_created} new)'
        ))

        # ------------------------------------------------------------------
        # Exams: one published with marks (so report cards, ranks and the
        # parent's Today card show something), one draft awaiting marks (so a
        # teacher can try entering them).
        # ------------------------------------------------------------------
        by_name = {subject.name: subject for subject in subjects}
        exam_subjects = [by_name['Mathematics'], by_name['English'], by_name['Science']]
        admin = User.objects.filter(username='admin').first()

        unit_test, created = Exam.objects.get_or_create(
            school=school, name='Unit Test 1', academic_year=ACADEMIC_YEAR,
            defaults={
                'start_date': today - timedelta(days=21),
                'end_date': today - timedelta(days=19),
                'created_by': admin,
            },
        )
        for subject in exam_subjects:
            ExamPaper.objects.get_or_create(
                exam=unit_test, classroom=class_5a, subject=subject,
                defaults={'max_marks': 50, 'pass_marks': 18},
            )
        scores = {
            'ABC-5A-01': (46, 44, 48),   # Kavya
            'ABC-5A-02': (31, 38, 29),   # Rahul
            'ADM001': (42, 35, 40),      # Aarav
        }
        for admission_number, marks in scores.items():
            student = students.get(admission_number)
            if not student:
                continue
            for subject, obtained in zip(exam_subjects, marks):
                paper = ExamPaper.objects.get(exam=unit_test, classroom=class_5a, subject=subject)
                Mark.objects.get_or_create(
                    paper=paper, student=student,
                    defaults={'marks_obtained': obtained, 'entered_by': teacher},
                )
        if created:
            publish_exam(unit_test, allow_incomplete=True)

        quarterly, _ = Exam.objects.get_or_create(
            school=school, name='Quarterly Exam', academic_year=ACADEMIC_YEAR,
            defaults={
                'start_date': today + timedelta(days=10),
                'end_date': today + timedelta(days=16),
                'created_by': admin,
            },
        )
        for subject in subjects:
            ExamPaper.objects.get_or_create(exam=quarterly, classroom=class_5a, subject=subject)

        self.stdout.write(self.style.SUCCESS(
            f'Exams ready: {unit_test.name} (published, {Mark.objects.filter(paper__exam=unit_test).count()} marks), '
            f'{quarterly.name} (draft, awaiting marks)'
        ))

        self.stdout.write('')
        self.stdout.write(self.style.MIGRATE_HEADING('Demo data ready for manual testing.'))
