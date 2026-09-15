from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import MethodNotAllowed, PermissionDenied
from rest_framework.response import Response

from apps.notifications.services import NotificationService
from apps.schools.services import attach_user_to_school, get_school_for
from apps.students.models import Class, Student

from .models import Attendance
from .permissions import IsAttendanceAuthorized
from .serializers import AttendanceCorrectionSerializer, AttendanceSerializer, MarkAttendanceSerializer


class AttendanceViewSet(viewsets.ModelViewSet):
    """
    Daily attendance.

    - GET  /api/v1/attendance/?class_id=&date=&student_id=&from_date=&to_date=
    - POST /api/v1/attendance/mark/        mark a whole class in one request
    - GET  /api/v1/attendance/sheet/?class_id=&date=   the day's register
    - GET  /api/v1/attendance/summary/?student_id=     percentage + recent days
    """

    serializer_class = AttendanceSerializer
    permission_classes = [permissions.IsAuthenticated, IsAttendanceAuthorized]

    def get_serializer_class(self):
        if self.action in ('update', 'partial_update'):
            return AttendanceCorrectionSerializer
        return AttendanceSerializer

    def create(self, request, *args, **kwargs):
        # Attendance is taken a class at a time through mark/, which checks the
        # class, the students in it, and notifies parents. A bare create did
        # none of that.
        raise MethodNotAllowed('POST', detail="Mark attendance through /api/v1/attendance/mark/.")

    def perform_update(self, serializer):
        previous_status = serializer.instance.status
        record = serializer.save(marked_by=self.request.user)
        if record.status != previous_status:
            NotificationService.create_attendance_notifications([record])

    def get_queryset(self):
        user = self.request.user
        school = get_school_for(user)

        queryset = Attendance.objects.select_related(
            'student', 'classroom', 'marked_by'
        )
        if not (user.is_superuser and not user.school):
            queryset = queryset.filter(school=school)

        if user.role == 'PARENT':
            queryset = queryset.filter(student__parents=user)
        elif user.role == 'TEACHER':
            queryset = queryset.filter(classroom__teachers=user)

        params = self.request.query_params

        class_id = params.get('class_id')
        if class_id:
            queryset = queryset.filter(classroom_id=class_id)

        student_id = params.get('student_id')
        if student_id:
            queryset = queryset.filter(student_id=student_id)

        on_date = params.get('date')
        if on_date:
            queryset = queryset.filter(date=on_date)

        from_date = params.get('from_date')
        if from_date:
            queryset = queryset.filter(date__gte=from_date)

        to_date = params.get('to_date')
        if to_date:
            queryset = queryset.filter(date__lte=to_date)

        status_filter = params.get('status')
        if status_filter:
            queryset = queryset.filter(status=status_filter.upper())

        return queryset.distinct()

    # ------------------------------------------------------------------
    # marking
    # ------------------------------------------------------------------

    def _assert_can_mark(self, user, classroom):
        if classroom.can_mark_attendance(user):
            return
        if classroom.class_teacher_id and classroom.teachers.filter(id=user.id).exists():
            raise PermissionDenied(
                "Attendance for this class is taken by its class teacher."
            )
        raise PermissionDenied(
            "You can only mark attendance for classes assigned to you."
        )

    @action(detail=False, methods=['post'], url_path='mark')
    def mark(self, request):
        """
        Marks a whole class for one day.

        Re-marking the same day corrects the existing rows instead of adding
        duplicates, because a teacher does revise a mark when a child turns up
        late. The whole submission is one transaction: a half-marked register
        is worse than none.
        """
        serializer = MarkAttendanceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        user = request.user
        school = attach_user_to_school(user)

        classroom = Class.objects.filter(id=data['classroom'], school=school).first()
        if classroom is None:
            return Response(
                {"detail": "That class does not exist in this school."},
                status=status.HTTP_404_NOT_FOUND,
            )
        self._assert_can_mark(user, classroom)

        entries = data['entries']
        student_ids = [entry['student'] for entry in entries]
        students = {
            student.id: student
            for student in Student.objects.filter(
                id__in=student_ids, school=school, class_enrolled=classroom
            )
        }

        unknown = [sid for sid in student_ids if sid not in students]
        if unknown:
            return Response(
                {
                    "detail": "Some students are not enrolled in this class.",
                    "student_ids": unknown,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Only rows whose status actually changed are worth telling a parent
        # about: re-saving an unchanged register must not send the whole class
        # a second notification.
        existing = {
            record.student_id: record.status
            for record in Attendance.objects.filter(
                student_id__in=student_ids, date=data['date']
            )
        }

        created = updated = 0
        changed_records = []
        with transaction.atomic():
            for entry in entries:
                record, was_created = Attendance.objects.update_or_create(
                    student=students[entry['student']],
                    date=data['date'],
                    defaults={
                        'school': school,
                        'classroom': classroom,
                        'status': entry['status'],
                        'note': entry.get('note', ''),
                        'marked_by': user,
                    },
                )
                if was_created:
                    created += 1
                    changed_records.append(record)
                else:
                    updated += 1
                    if existing.get(entry['student']) != entry['status']:
                        changed_records.append(record)

        notified = NotificationService.create_attendance_notifications(changed_records)

        return Response(
            {
                'date': data['date'],
                'classroom': classroom.id,
                'classroom_name': str(classroom),
                'created': created,
                'updated': updated,
                'total': len(entries),
                'parents_notified': len(notified),
            },
            status=status.HTTP_200_OK,
        )

    # ------------------------------------------------------------------
    # the day's register
    # ------------------------------------------------------------------

    @action(detail=False, methods=['get'], url_path='sheet')
    def sheet(self, request):
        """
        The register a teacher opens: every student in the class, with whatever
        was already marked for that date. Students with no row yet come back
        with status null so the screen can default them to Present.
        """
        user = request.user
        school = get_school_for(user)

        class_id = request.query_params.get('class_id')
        if not class_id:
            return Response(
                {"detail": "class_id is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        classroom = Class.objects.filter(id=class_id, school=school).first()
        if classroom is None:
            return Response(
                {"detail": "That class does not exist in this school."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if user.role == 'TEACHER' and not classroom.teachers.filter(id=user.id).exists():
            raise PermissionDenied("That class is not assigned to you.")
        if user.role == 'PARENT':
            raise PermissionDenied("Parents cannot open a class register.")

        on_date = request.query_params.get('date') or str(timezone.localdate())

        students = Student.objects.filter(
            class_enrolled=classroom, is_active=True
        ).order_by('admission_number')

        marked = {
            record.student_id: record
            for record in Attendance.objects.filter(
                classroom=classroom, date=on_date
            )
        }

        rows = []
        for student in students:
            record = marked.get(student.id)
            rows.append({
                'student': student.id,
                'student_name': student.full_name,
                'admission_number': student.admission_number,
                'status': record.status if record else None,
                'note': record.note if record else '',
            })

        return Response({
            'classroom': classroom.id,
            'classroom_name': str(classroom),
            'date': on_date,
            'already_marked': bool(marked),
            'student_count': len(rows),
            'students': rows,
        }, status=status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # parent / admin summary
    # ------------------------------------------------------------------

    @action(detail=False, methods=['get'], url_path='summary')
    def summary(self, request):
        """
        Attendance percentage and recent days for one student.

        A parent may only ask about their own child; the queryset scoping above
        already enforces that, so an unrelated student simply has no records.
        """
        student_id = request.query_params.get('student_id')
        if not student_id:
            return Response(
                {"detail": "student_id is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        records = self.get_queryset().filter(student_id=student_id)

        counts = records.aggregate(
            total=Count('id'),
            present=Count('id', filter=Q(status=Attendance.Status.PRESENT)),
            absent=Count('id', filter=Q(status=Attendance.Status.ABSENT)),
            late=Count('id', filter=Q(status=Attendance.Status.LATE)),
            excused=Count('id', filter=Q(status=Attendance.Status.EXCUSED)),
        )

        total = counts['total'] or 0
        # Late still counts as attending - the child was in class.
        attended = (counts['present'] or 0) + (counts['late'] or 0)
        percentage = round((attended / total) * 100, 1) if total else None

        recent = AttendanceSerializer(records.order_by('-date')[:30], many=True).data

        return Response({
            'student_id': int(student_id),
            'days_recorded': total,
            'present': counts['present'] or 0,
            'absent': counts['absent'] or 0,
            'late': counts['late'] or 0,
            'excused': counts['excused'] or 0,
            'attendance_percentage': percentage,
            'recent': recent,
        }, status=status.HTTP_200_OK)
