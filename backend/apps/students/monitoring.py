"""
What the admin watches: the school at a glance, one student, one class, one
teacher. Read-only views over records the other apps own - nothing here
stores anything.

Each view answers one screen in one request, with a fixed number of queries
however large the school.
"""

from datetime import timedelta

from django.contrib.auth import get_user_model
from django.db.models import Count, Max, Q
from django.utils import timezone
from rest_framework import permissions
from rest_framework.exceptions import NotFound, PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.announcements.models import Announcement
from apps.attendance.models import Attendance
from apps.exams.models import Exam, ExamPaper, Mark
from apps.exams.services import report_card
from apps.homework.models import Homework
from apps.schools.services import get_school_for
from apps.timetable.models import TimetableSlot
from apps.timetable.views import group_week

from .access import student_for_report
from .models import Class, Student, normalize_academic_year

User = get_user_model()

ATTENDED = [Attendance.Status.PRESENT, Attendance.Status.LATE]


def _name(user):
    if user is None:
        return None
    return f'{user.first_name} {user.last_name}'.strip() or user.username


def _percentage(attended, total):
    return round(attended * 100 / total, 1) if total else None


def _require_admin(user):
    if not (user.is_superuser or user.role == 'ADMIN'):
        raise PermissionDenied('Only school administrators can see this.')


def _current_year(school, requested):
    if requested:
        return normalize_academic_year(requested)
    latest = Class.objects.filter(school=school, is_active=True).aggregate(year=Max('academic_year'))['year']
    return latest


class DashboardSummaryView(APIView):
    """
    GET /api/v1/dashboard/summary/?academic_year=2026-2027
    Real school-wide totals for the admin dashboard - not the length of a
    loaded page - plus the gaps an admin should fix.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        _require_admin(request.user)
        school = get_school_for(request.user)
        year = _current_year(school, request.query_params.get('academic_year'))
        today = timezone.localdate()

        classes = Class.objects.filter(school=school, is_active=True)
        if year:
            classes = classes.filter(academic_year=year)
        class_ids = list(classes.values_list('id', flat=True))

        students = Student.objects.filter(school=school, is_active=True)
        people = User.objects.filter(school=school, is_active=True)

        todays = Attendance.objects.filter(school=school, date=today, classroom_id__in=class_ids)
        attendance_counts = todays.aggregate(
            classes_marked=Count('classroom', distinct=True),
            present=Count('id', filter=Q(status=Attendance.Status.PRESENT)),
            absent=Count('id', filter=Q(status=Attendance.Status.ABSENT)),
            late=Count('id', filter=Q(status=Attendance.Status.LATE)),
            excused=Count('id', filter=Q(status=Attendance.Status.EXCUSED)),
        )
        exams = Exam.objects.filter(school=school)
        if year:
            exams = exams.filter(academic_year=year)

        return Response({
            'academic_year': year,
            'date': today,
            'counts': {
                'students': students.count(),
                'classes': len(class_ids),
                'teachers': people.filter(role=User.Role.TEACHER).count(),
                'parents': people.filter(role=User.Role.PARENT).count(),
            },
            'attendance_today': {
                'classes_total': len(class_ids),
                **attendance_counts,
            },
            'exams': exams.aggregate(
                published=Count('id', filter=Q(is_published=True)),
                draft=Count('id', filter=Q(is_published=False)),
            ),
            'homework': {
                'active': Homework.objects.filter(school=school, is_active=True, due_date__gte=today).count(),
                'set_last_7_days': Homework.objects.filter(
                    school=school, is_active=True, assigned_date__gte=today - timedelta(days=7)
                ).count(),
            },
            'announcements_last_7_days': Announcement.objects.filter(
                school=school, is_active=True, published_at__date__gte=today - timedelta(days=7)
            ).count(),
            'needs_attention': {
                'teachers_without_class': people.filter(role=User.Role.TEACHER)
                .exclude(assigned_classes__in=class_ids).count(),
                'classes_without_class_teacher': classes.filter(class_teacher__isnull=True).count(),
                'students_without_class': students.filter(class_enrolled__isnull=True).count(),
                'students_without_parent': students.filter(parents__isnull=True).count(),
            },
        })


class StudentProfileView(APIView):
    """
    GET /api/v1/students/{id}/profile/
    Everything about one student: class, parents, attendance, homework,
    results and class history. Admin: any student. Teacher: their students.
    Parent: their own child (results only once published).
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        student = student_for_report(request, pk)
        user = request.user
        classroom = student.class_enrolled
        today = timezone.localdate()

        records = Attendance.objects.filter(student=student)
        if classroom is not None:
            records = records.filter(classroom=classroom)
        counts = records.aggregate(
            total=Count('id'),
            present=Count('id', filter=Q(status=Attendance.Status.PRESENT)),
            absent=Count('id', filter=Q(status=Attendance.Status.ABSENT)),
            late=Count('id', filter=Q(status=Attendance.Status.LATE)),
            excused=Count('id', filter=Q(status=Attendance.Status.EXCUSED)),
        )

        homework = Homework.objects.none()
        if classroom is not None:
            homework = Homework.objects.filter(classroom=classroom, is_active=True).filter(
                Q(student__isnull=True) | Q(student=student)
            )

        cards = report_card(student, published_only=user.role == 'PARENT')

        return Response({
            'student': {
                'id': student.id,
                'full_name': student.full_name,
                'admission_number': student.admission_number,
                'date_of_birth': student.date_of_birth,
                'is_active': student.is_active,
            },
            'classroom': None if classroom is None else {
                'id': classroom.id,
                'name': classroom.name,
                'section': classroom.section,
                'academic_year': classroom.academic_year,
                'class_teacher_id': classroom.class_teacher_id,
                'class_teacher_name': _name(classroom.class_teacher),
            },
            'parents': [
                {'id': parent.id, 'full_name': _name(parent), 'phone_number': parent.phone_number or '',
                 'email': parent.email or ''}
                for parent in student.parents.filter(is_active=True).order_by('first_name')
            ],
            'attendance': {
                'days_recorded': counts['total'],
                'present': counts['present'],
                'absent': counts['absent'],
                'late': counts['late'],
                'excused': counts['excused'],
                'percentage': _percentage(counts['present'] + counts['late'], counts['total']),
                'recent': [
                    {'date': row.date, 'status': row.status, 'note': row.note}
                    for row in records.order_by('-date')[:30]
                ],
            },
            'homework': {
                'active': homework.filter(due_date__gte=today).count(),
                'recent': [
                    {'id': item.id, 'title': item.title, 'subject': item.subject,
                     'assigned_date': item.assigned_date, 'due_display': item.due_display,
                     'is_for_this_child_only': item.student_id is not None}
                    for item in homework.order_by('-assigned_date', '-id')[:10]
                ],
            },
            'results': [
                {key: card[key] for key in (
                    'exam', 'exam_name', 'academic_year', 'classroom_name', 'total', 'max_total',
                    'percentage', 'grade', 'result', 'rank', 'class_size', 'is_published',
                )}
                for card in cards
            ],
            'class_history': [
                {'academic_year': row.academic_year, 'classroom_name': f'{row.classroom.name} - {row.classroom.section}',
                 'is_current': row.is_current, 'start_date': row.start_date, 'end_date': row.end_date}
                for row in student.enrollments.select_related('classroom').order_by('-academic_year')
            ],
        })


class ClassOverviewView(APIView):
    """
    GET /api/v1/classes/{id}/overview/
    One class: its teachers and subjects, today's attendance, every student's
    attendance percentage, recent homework and its exams. Admin, or a teacher
    of that class.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        user = request.user
        school = get_school_for(user)
        classroom = Class.objects.select_related('class_teacher').filter(id=pk, school=school).first()
        if classroom is None:
            raise NotFound('Class not found.')
        if user.role == 'TEACHER':
            if not classroom.teachers.filter(id=user.id).exists():
                raise NotFound('Class not found.')
        elif not (user.is_superuser or user.role == 'ADMIN'):
            raise PermissionDenied('Only staff can see a class overview.')

        today = timezone.localdate()
        students = (
            Student.objects.filter(class_enrolled=classroom, is_active=True)
            .annotate(
                days=Count('attendance_records', filter=Q(attendance_records__classroom=classroom), distinct=True),
                attended=Count('attendance_records', filter=Q(
                    attendance_records__classroom=classroom, attendance_records__status__in=ATTENDED), distinct=True),
                parent_count=Count('parents', filter=Q(parents__is_active=True), distinct=True),
            )
            .order_by('first_name', 'last_name')
        )

        todays = Attendance.objects.filter(classroom=classroom, date=today).aggregate(
            marked=Count('id'),
            present=Count('id', filter=Q(status=Attendance.Status.PRESENT)),
            absent=Count('id', filter=Q(status=Attendance.Status.ABSENT)),
            late=Count('id', filter=Q(status=Attendance.Status.LATE)),
            excused=Count('id', filter=Q(status=Attendance.Status.EXCUSED)),
        )

        subjects = {}
        for slot in TimetableSlot.objects.filter(classroom=classroom).select_related('subject', 'teacher'):
            entry = subjects.setdefault(slot.subject.name, {'subject_name': slot.subject.name, 'teachers': set(),
                                                             'periods_per_week': 0})
            entry['periods_per_week'] += 1
            if slot.teacher:
                entry['teachers'].add(_name(slot.teacher))

        student_rows = [
            {'id': s.id, 'full_name': s.full_name, 'admission_number': s.admission_number,
             'attendance_percentage': _percentage(s.attended, s.days), 'days_recorded': s.days,
             'parent_count': s.parent_count}
            for s in students
        ]
        homework = Homework.objects.filter(classroom=classroom, is_active=True)

        return Response({
            'classroom': {
                'id': classroom.id, 'name': classroom.name, 'section': classroom.section,
                'academic_year': classroom.academic_year, 'student_count': len(student_rows),
            },
            'class_teacher': None if classroom.class_teacher is None else {
                'id': classroom.class_teacher_id, 'full_name': _name(classroom.class_teacher),
            },
            'teachers': [
                {'id': t.id, 'full_name': _name(t), 'is_class_teacher': t.id == classroom.class_teacher_id}
                for t in classroom.teachers.filter(is_active=True).order_by('first_name')
            ],
            'subjects': sorted(
                ({**entry, 'teachers': sorted(entry['teachers'])} for entry in subjects.values()),
                key=lambda entry: entry['subject_name'],
            ),
            'attendance_today': {
                'date': today,
                'is_marked': todays['marked'] > 0,
                'not_marked': max(len(student_rows) - todays['marked'], 0),
                **todays,
            },
            'students': student_rows,
            'homework': {
                'active': homework.filter(due_date__gte=today).count(),
                'recent': [
                    {'id': h.id, 'title': h.title, 'subject': h.subject, 'due_display': h.due_display,
                     'assigned_by_name': _name(h.assigned_by)}
                    for h in homework.select_related('assigned_by').order_by('-assigned_date', '-id')[:5]
                ],
            },
            'exams': [
                {'id': exam['exam_id'], 'name': exam['exam__name'], 'is_published': exam['exam__is_published'],
                 'papers': exam['papers']}
                for exam in ExamPaper.objects.filter(classroom=classroom)
                .values('exam_id', 'exam__name', 'exam__is_published')
                .annotate(papers=Count('id'))
                .order_by('-exam_id')
            ],
        })


class TeacherProfileView(APIView):
    """
    GET /api/v1/auth/staff/{id}/profile/
    One teacher, for the admin: classes (and which they are class teacher
    of), subjects, their week, and what they have done in the last 30 days.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        _require_admin(request.user)
        school = get_school_for(request.user)
        teacher = User.objects.filter(id=pk, role=User.Role.TEACHER, school=school).first()
        if teacher is None:
            raise NotFound('Teacher not found.')

        since = timezone.localdate() - timedelta(days=30)
        slots = TimetableSlot.objects.filter(teacher=teacher).select_related('classroom', 'subject', 'teacher')

        subjects = {}
        for slot in slots:
            entry = subjects.setdefault(slot.subject.name, {'subject_name': slot.subject.name, 'classes': set(),
                                                             'periods_per_week': 0})
            entry['periods_per_week'] += 1
            entry['classes'].add(f'{slot.classroom.name} - {slot.classroom.section}')

        homework = Homework.objects.filter(assigned_by=teacher, assigned_date__gte=since)
        announcements = Announcement.objects.filter(created_by=teacher, published_at__date__gte=since)

        return Response({
            'teacher': {
                'id': teacher.id, 'full_name': _name(teacher), 'username': teacher.username,
                'phone_number': teacher.phone_number or '', 'email': teacher.email or '',
                'is_active': teacher.is_active,
            },
            'classes': [
                {'id': c.id, 'name': f'{c.name} - {c.section}', 'academic_year': c.academic_year,
                 'is_class_teacher': c.class_teacher_id == teacher.id, 'student_count': c.active_students}
                for c in Class.objects.filter(teachers=teacher, is_active=True)
                .annotate(active_students=Count('students', filter=Q(students__is_active=True), distinct=True))
                .order_by('name', 'section')
            ],
            'subjects': sorted(
                ({**entry, 'classes': sorted(entry['classes'])} for entry in subjects.values()),
                key=lambda entry: entry['subject_name'],
            ),
            'timetable': group_week(slots),
            'activity_last_30_days': {
                'homework_set': homework.count(),
                'recent_homework': [
                    {'id': h.id, 'title': h.title, 'subject': h.subject, 'assigned_date': h.assigned_date,
                     'classroom_name': f'{h.classroom.name} - {h.classroom.section}'}
                    for h in homework.select_related('classroom').order_by('-assigned_date', '-id')[:5]
                ],
                'attendance_days_marked': Attendance.objects.filter(marked_by=teacher, date__gte=since)
                .values('date').distinct().count(),
                'announcements_posted': announcements.count(),
                'marks_entered': Mark.objects.filter(entered_by=teacher, updated_at__date__gte=since).count(),
            },
        })
