from django.db.models import Q
from collections import defaultdict

from django.utils import timezone
from rest_framework import permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from apps.schools.services import attach_user_to_school, get_school_for
from apps.students.models import Class

from .models import Subject, TimetableSlot
from .serializers import SubjectSerializer, TimetableSlotSerializer


def group_week(slots):
    """Groups slots into the six-day week the UI draws (Sunday only if used)."""
    buckets = defaultdict(list)
    for slot in slots:
        buckets[slot.weekday].append(slot)

    return [
        {
            'weekday': weekday,
            'weekday_name': label,
            'periods': TimetableSlotSerializer(
                sorted(buckets.get(weekday, []), key=lambda s: s.period),
                many=True,
            ).data,
        }
        for weekday, label in TimetableSlot.Weekday.choices
        if weekday != TimetableSlot.Weekday.SUNDAY or buckets.get(weekday)
    ]


class IsAdminOrReadOnly(permissions.BasePermission):
    """
    Everyone signed in at an active school reads; only an admin writes.

    A timetable is a school-wide schedule - a teacher editing their own row
    would silently move a class for everyone else.
    """

    message = "Only school administrators can change the timetable."

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if user.is_superuser:
            return True

        school = get_school_for(user)
        if not school or not school.is_active:
            return False

        if request.method in permissions.SAFE_METHODS:
            return True
        return user.role == 'ADMIN'

    def has_object_permission(self, request, view, obj):
        if request.user.is_superuser:
            return True
        if obj.school != get_school_for(request.user):
            return False
        if request.method in permissions.SAFE_METHODS:
            return True
        return request.user.role == 'ADMIN'


class SubjectViewSet(viewsets.ModelViewSet):
    """
    GET  /api/v1/subjects/      the school's subject list
    POST /api/v1/subjects/      admin only
    """

    serializer_class = SubjectSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrReadOnly]
    pagination_class = None  # a school has tens of subjects, not pages of them

    def get_queryset(self):
        user = self.request.user
        queryset = Subject.objects.all()
        if not (user.is_superuser and not user.school):
            queryset = queryset.filter(school=get_school_for(user))

        is_active = self.request.query_params.get('is_active')
        if is_active is not None:
            queryset = queryset.filter(
                is_active=is_active.lower() in ('1', 'true', 'yes')
            )
        return queryset

    def perform_create(self, serializer):
        serializer.save(school=attach_user_to_school(self.request.user))


class TimetableViewSet(viewsets.ModelViewSet):
    """
    The weekly schedule.

    - GET  /api/v1/timetable/?class_id=&weekday=&teacher_id=
    - GET  /api/v1/timetable/week/?class_id=     one class, grouped by weekday
    - GET  /api/v1/timetable/my/                 the signed-in teacher's week
    - GET  /api/v1/timetable/today/?class_id=    just today's periods
    - POST/PATCH/DELETE                          admin only
    """

    serializer_class = TimetableSlotSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrReadOnly]
    pagination_class = None  # a week is bounded; paging it would break the grid

    def get_queryset(self):
        user = self.request.user
        queryset = TimetableSlot.objects.select_related(
            'classroom', 'subject', 'teacher'
        )
        if not (user.is_superuser and not user.school):
            queryset = queryset.filter(school=get_school_for(user))

        # Parents only ever see the classes their children are in.
        if user.role == 'PARENT':
            child_classes = user.children.filter(
                is_active=True, class_enrolled__isnull=False
            ).values_list('class_enrolled_id', flat=True)
            queryset = queryset.filter(classroom_id__in=list(child_classes))
        # Teachers see the classes they are assigned to, plus any period they
        # teach elsewhere - not every class in the school.
        elif user.role == 'TEACHER':
            queryset = queryset.filter(Q(classroom__teachers=user) | Q(teacher=user)).distinct()

        params = self.request.query_params

        class_id = params.get('class_id')
        if class_id:
            queryset = queryset.filter(classroom_id=class_id)

        weekday = params.get('weekday')
        if weekday is not None and weekday != '':
            queryset = queryset.filter(weekday=weekday)

        teacher_id = params.get('teacher_id')
        if teacher_id:
            queryset = queryset.filter(teacher_id=teacher_id)

        subject_id = params.get('subject_id')
        if subject_id:
            queryset = queryset.filter(subject_id=subject_id)

        return queryset

    def perform_create(self, serializer):
        user = self.request.user
        school = attach_user_to_school(user)
        serializer.save(school=school)

    def perform_update(self, serializer):
        serializer.save(school=get_school_for(self.request.user))

    # ------------------------------------------------------------------
    # shaped reads
    # ------------------------------------------------------------------

    def _grouped_by_weekday(self, slots):
        return group_week(slots)


    @action(detail=False, methods=['get'], url_path='week')
    def week(self, request):
        """One class's full week, grouped by day."""
        class_id = request.query_params.get('class_id')
        if not class_id:
            return Response(
                {"detail": "class_id is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        classroom = Class.objects.filter(
            id=class_id, school=get_school_for(request.user)
        ).first()
        if classroom is None:
            return Response(
                {"detail": "That class does not exist in this school."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # get_queryset already scopes a parent to their children's classes, so
        # asking for someone else's class simply returns an empty week.
        slots = self.get_queryset().filter(classroom=classroom)
        if request.user.role == 'PARENT' and not slots.exists():
            raise PermissionDenied("That class is not one of your children's.")
        if (
            request.user.role == 'TEACHER'
            and not classroom.teachers.filter(id=request.user.id).exists()
            and not slots.exists()
        ):
            raise PermissionDenied("You can only see the timetable of classes you teach.")

        return Response({
            'classroom': classroom.id,
            'classroom_name': str(classroom),
            'days': self._grouped_by_weekday(slots),
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['get'], url_path='my')
    def my_schedule(self, request):
        """
        The signed-in teacher's own week: which class and subject each period,
        so they can see where they are meant to be without hunting through
        every class's grid.
        """
        user = request.user
        if user.role != 'TEACHER' and not user.is_superuser:
            return Response(
                {"detail": "Only teachers have a personal timetable."},
                status=status.HTTP_403_FORBIDDEN,
            )

        slots = self.get_queryset().filter(teacher=user)
        today = timezone.localdate().weekday()

        return Response({
            'teacher': user.id,
            'today': today,
            'days': self._grouped_by_weekday(slots),
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['get'], url_path='today')
    def today(self, request):
        """Just today's periods - for a class, or for the signed-in teacher."""
        weekday = timezone.localdate().weekday()
        slots = self.get_queryset().filter(weekday=weekday)

        class_id = request.query_params.get('class_id')
        if not class_id and request.user.role == 'TEACHER':
            slots = slots.filter(teacher=request.user)

        return Response({
            'weekday': weekday,
            'weekday_name': TimetableSlot.Weekday(weekday).label,
            'periods': TimetableSlotSerializer(
                slots.order_by('period'), many=True
            ).data,
        }, status=status.HTTP_200_OK)
