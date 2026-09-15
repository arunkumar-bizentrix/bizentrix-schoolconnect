"""
The parent's Today screen, in one request.

A parent opens the app to answer four questions: did my child reach school,
what are they studying right now, what homework came home, and how did the
last exam go. Four screens and four round trips for that is why parents stop
opening a school app.
"""

from datetime import timedelta

from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.attendance.models import Attendance
from apps.exams.services import report_card
from apps.homework.models import Homework
from apps.timetable.models import TimetableSlot

HOMEWORK_LOOKAHEAD_DAYS = 3


def _name(user):
    if user is None:
        return None
    return f'{user.first_name} {user.last_name}'.strip() or user.username


def _homework_row(homework, today):
    return {
        'id': homework.id,
        'title': homework.title,
        'subject': homework.subject,
        'assigned_date': homework.assigned_date,
        'due_date': homework.due_date,
        'due_display': homework.due_display,
        'due_today': homework.due_date == today,
        'is_for_this_child_only': homework.student_id is not None,
    }


def build_child_today(child, today):
    classroom = child.class_enrolled

    # --- attendance -------------------------------------------------------
    records = Attendance.objects.filter(student=child)
    if classroom is not None:
        records = records.filter(classroom=classroom)
    today_record = records.filter(date=today).first()
    counts = records.aggregate(
        total=Count('id'),
        attended=Count('id', filter=Q(status__in=[Attendance.Status.PRESENT, Attendance.Status.LATE])),
    )
    total = counts['total'] or 0
    attendance = {
        'status': today_record.status if today_record else None,
        'note': today_record.note if today_record else '',
        'marked': today_record is not None,
        'days_recorded': total,
        'percentage': round(counts['attended'] * 100 / total, 1) if total else None,
    }

    # --- today's periods --------------------------------------------------
    periods = []
    if classroom is not None:
        slots = TimetableSlot.objects.filter(
            classroom=classroom, weekday=today.weekday()
        ).select_related('subject', 'teacher').order_by('period')
        periods = [
            {
                'period': slot.period,
                'subject_name': slot.subject.name,
                'teacher_name': _name(slot.teacher),
                'start_time': slot.start_time,
                'end_time': slot.end_time,
                'time_display': slot.time_display,
                'room': slot.room,
            }
            for slot in slots
        ]

    # --- homework ---------------------------------------------------------
    homework_today, homework_due_soon = [], []
    if classroom is not None:
        visible = Homework.objects.filter(
            classroom=classroom, is_active=True
        ).filter(Q(student__isnull=True) | Q(student=child))

        assigned_today = list(visible.filter(assigned_date=today).order_by('due_date', 'due_time'))
        homework_today = [_homework_row(item, today) for item in assigned_today]

        due_soon = visible.filter(
            due_date__gte=today,
            due_date__lte=today + timedelta(days=HOMEWORK_LOOKAHEAD_DAYS),
        ).exclude(id__in=[item.id for item in assigned_today]).order_by('due_date', 'due_time')[:10]
        homework_due_soon = [_homework_row(item, today) for item in due_soon]

    # --- last published exam ---------------------------------------------
    cards = report_card(child, published_only=True)
    latest = cards[0] if cards else None
    latest_result = None
    if latest is not None:
        latest_result = {
            key: latest[key]
            for key in (
                'exam', 'exam_name', 'total', 'max_total', 'percentage',
                'grade', 'rank', 'class_size', 'result',
            )
        }

    return {
        'student': child.id,
        'student_name': child.full_name,
        'classroom': classroom.id if classroom else None,
        'classroom_name': f'{classroom.name} - {classroom.section}' if classroom else None,
        'class_teacher_name': _name(classroom.class_teacher) if classroom else None,
        'attendance': attendance,
        'periods': periods,
        'homework_today': homework_today,
        'homework_due_soon': homework_due_soon,
        'latest_result': latest_result,
    }


class ParentTodayView(APIView):
    """
    GET /api/v1/parent/today/
    GET /api/v1/parent/today/?student_id=12   one child only

    Everything a parent checks each day, for each of their own children.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role != 'PARENT':
            return Response(
                {'detail': 'The Today screen is for parents.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        children = user.children.filter(is_active=True).select_related(
            'class_enrolled', 'class_enrolled__class_teacher'
        ).order_by('first_name')

        student_id = request.query_params.get('student_id')
        if student_id:
            children = children.filter(id=student_id)
            if not children.exists():
                return Response(
                    {'detail': 'You can only see your own children.'},
                    status=status.HTTP_403_FORBIDDEN,
                )

        today = timezone.localdate()
        return Response({
            'date': today,
            'weekday': today.strftime('%A'),
            'children': [build_child_today(child, today) for child in children],
        })
