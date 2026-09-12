from django.db.models import Q
from django.utils import timezone
from rest_framework import viewsets, permissions, filters
from rest_framework.exceptions import PermissionDenied
from apps.notifications.services import NotificationService
from apps.schools.services import attach_user_to_school, get_school_for
from apps.students.models import Class, Student, normalize_academic_year
from .models import Homework
from .serializers import HomeworkSerializer
from .permissions import IsHomeworkAuthorized


class HomeworkViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing Homework with role-based scoping, strict tenant isolation,
    and advanced multi-parameter filtering.
    - List homework: GET /api/v1/homework/
    - Filters: ?academic_year=2025-2026&class_id=1&section=A&student=Arun&subject=Science&from_date=2025-08-01&to_date=2025-08-30
    """
    serializer_class = HomeworkSerializer
    permission_classes = [permissions.IsAuthenticated, IsHomeworkAuthorized]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['title', 'subject', 'description']
    ordering_fields = ['due_date', 'assigned_date', 'created_at']

    def get_queryset(self):
        user = self.request.user
        school = get_school_for(user)

        if user.is_superuser and not user.school:
            queryset = Homework.objects.select_related('school', 'classroom', 'assigned_by', 'student').all()
        else:
            queryset = Homework.objects.select_related(
                'school', 'classroom', 'assigned_by', 'student'
            ).filter(school=school, is_active=True)

        # Role-based restriction: Parents only see homework for their children's enrolled classes or targeted specifically to them
        children_classes = []
        if user.role == 'PARENT':
            children = user.children.filter(is_active=True)
            children_classes = list(children.filter(
                class_enrolled__isnull=False,
            ).values_list('class_enrolled_id', flat=True))
            children_ids = list(children.values_list('id', flat=True))
            queryset = queryset.filter(
                Q(classroom_id__in=children_classes, student__isnull=True) |
                Q(student_id__in=children_ids)
            )
        elif user.role == 'TEACHER':
            queryset = queryset.filter(classroom__teachers=user)

        params = self.request.query_params

        # Filter: academic_year (e.g. 2025-2026 or 2025-26)
        academic_year = params.get('academic_year')
        if academic_year:
            norm_year = normalize_academic_year(academic_year)
            queryset = queryset.filter(classroom__academic_year__iexact=norm_year)

        # Filter: class_id / class
        class_id = params.get('class_id') or params.get('class')
        if class_id:
            # Multi-tenant security: Ensure class belongs to user's school
            if not user.is_superuser:
                class_exists = Class.objects.filter(id=class_id, school=school).exists()
                if not class_exists:
                    return queryset.none()
            # Parent cannot query unlinked class_id
            if user.role == 'PARENT':
                try:
                    c_id = int(class_id)
                    if c_id not in children_classes:
                        return queryset.none()
                except (ValueError, TypeError):
                    return queryset.none()
            queryset = queryset.filter(classroom_id=class_id)

        # Filter: section
        section = params.get('section')
        if section:
            queryset = queryset.filter(classroom__section__iexact=section)

        # Filter: student_id / student (finds homework for that student's enrolled classes)
        student_param = params.get('student_id') or params.get('student')
        if student_param:
            if user.role == 'PARENT':
                student_qs = user.children.filter(is_active=True)
            else:
                student_qs = Student.objects.filter(school=school)

            if str(student_param).isdigit():
                student_qs = student_qs.filter(Q(id=int(student_param)) | Q(admission_number=str(student_param)))
            else:
                student_qs = student_qs.filter(
                    Q(first_name__icontains=student_param) |
                    Q(last_name__icontains=student_param) |
                    Q(admission_number__icontains=student_param)
                )

            student_obj = student_qs.first()
            if not student_obj:
                return queryset.none()

            # Collect classes student is/was enrolled in
            enrolled_class_ids = set()
            if student_obj.class_enrolled_id:
                enrolled_class_ids.add(student_obj.class_enrolled_id)
            for eid in student_obj.enrollments.values_list('classroom_id', flat=True):
                enrolled_class_ids.add(eid)

            queryset = queryset.filter(
                Q(student=student_obj) |
                (Q(classroom_id__in=enrolled_class_ids) & Q(student__isnull=True))
            )

        # Filter: subject
        subject = params.get('subject')
        if subject:
            queryset = queryset.filter(subject__iexact=subject)

        # Filter: assigned_by / teacher_id
        assigned_by = params.get('assigned_by') or params.get('teacher_id')
        if assigned_by:
            queryset = queryset.filter(assigned_by_id=assigned_by)

        # Filter: assigned_date
        assigned_date = params.get('assigned_date')
        if assigned_date:
            queryset = queryset.filter(assigned_date=assigned_date)

        # Filter: due_date
        due_date = params.get('due_date')
        if due_date:
            queryset = queryset.filter(due_date=due_date)

        # Filter: Date Ranges
        from_date = params.get('from_date') or params.get('assigned_date_gte') or params.get('assigned_date_after')
        if from_date:
            queryset = queryset.filter(assigned_date__gte=from_date)

        to_date = params.get('to_date') or params.get('assigned_date_lte') or params.get('assigned_date_before')
        if to_date:
            queryset = queryset.filter(assigned_date__lte=to_date)

        due_after = params.get('due_date_gte') or params.get('due_date_after')
        if due_after:
            queryset = queryset.filter(due_date__gte=due_after)

        due_before = params.get('due_date_lte') or params.get('due_date_before')
        if due_before:
            queryset = queryset.filter(due_date__lte=due_before)

        # Filter: is_active
        is_active = params.get('is_active')
        if is_active is not None:
            val = is_active.lower() in ['true', '1', 'yes']
            queryset = queryset.filter(is_active=val)

        return queryset.distinct()

    def perform_create(self, serializer):
        user = self.request.user
        school = attach_user_to_school(user)

        classroom = serializer.validated_data.get('classroom')
        if user.role == 'TEACHER':
            if not classroom or not classroom.teachers.filter(id=user.id).exists():
                raise PermissionDenied("You can only create homework for classes assigned to you.")

        extra = {'assigned_by': user}
        if 'assigned_date' not in serializer.validated_data:
            extra['assigned_date'] = timezone.localdate()
        if 'is_active' not in serializer.validated_data:
            extra['is_active'] = True

        if user.is_superuser and 'school' in serializer.validated_data:
            instance = serializer.save(**extra)
        else:
            instance = serializer.save(school=school, **extra)

        # Dispatch real-time in-app notifications to parents of this class
        NotificationService.create_homework_notifications(instance)
