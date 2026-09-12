from django.db.models import Q
from rest_framework import viewsets, permissions, filters
from rest_framework.exceptions import PermissionDenied
from apps.notifications.services import NotificationService
from apps.schools.services import attach_user_to_school, get_school_for
from apps.students.models import Class, normalize_academic_year
from .models import Announcement
from .serializers import AnnouncementSerializer
from .permissions import IsAnnouncementAuthorized


class AnnouncementViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing School Announcements & Circulars with tenant isolation
    and advanced multi-parameter filtering.
    - List announcements: GET /api/v1/announcements/
    - Filters: ?academic_year=2025-2026&priority=URGENT&audience_type=CLASS&class_id=1&from_date=2025-08-01&to_date=2025-08-30
    """
    serializer_class = AnnouncementSerializer
    permission_classes = [permissions.IsAuthenticated, IsAnnouncementAuthorized]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['title', 'content']
    ordering_fields = ['published_at', 'priority', 'created_at']

    def get_queryset(self):
        user = self.request.user
        school = get_school_for(user)

        if user.is_superuser and not user.school:
            queryset = Announcement.objects.select_related('school', 'target_class', 'created_by').all()
        else:
            queryset = Announcement.objects.select_related(
                'school', 'target_class', 'created_by'
            ).filter(school=school, is_active=True)

        # Role-based scoping: Parents only see SCHOOL circulars and CLASS notices for their children's classes
        parent_classes = []
        if user.role == 'PARENT':
            parent_classes = list(user.children.filter(
                is_active=True,
                class_enrolled__isnull=False,
            ).values_list('class_enrolled_id', flat=True))

            queryset = queryset.filter(
                Q(audience_type=Announcement.AudienceType.SCHOOL) |
                Q(audience_type=Announcement.AudienceType.CLASS, target_class_id__in=parent_classes)
            )
        elif user.role == 'TEACHER':
            queryset = queryset.filter(
                Q(audience_type=Announcement.AudienceType.SCHOOL) |
                Q(audience_type=Announcement.AudienceType.CLASS, target_class__teachers=user)
            )

        params = self.request.query_params

        # Filter: academic_year (e.g. 2025-2026 or 2025-26)
        academic_year = params.get('academic_year')
        if academic_year:
            norm_year = normalize_academic_year(academic_year)
            # Include all school-wide notices plus class notices matching the academic year
            queryset = queryset.filter(
                Q(audience_type=Announcement.AudienceType.SCHOOL) |
                Q(target_class__academic_year__iexact=norm_year)
            )

        # Filter: priority (NORMAL, IMPORTANT, URGENT)
        priority = params.get('priority')
        if priority:
            queryset = queryset.filter(priority=priority.upper())

        # Filter: audience_type (SCHOOL, CLASS)
        audience_type = params.get('audience_type')
        if audience_type:
            queryset = queryset.filter(audience_type=audience_type.upper())

        # Filter: class_id / target_class
        class_id = params.get('class_id') or params.get('target_class')
        if class_id:
            # Multi-tenant security: Ensure class belongs to user's school
            if not user.is_superuser:
                class_exists = Class.objects.filter(id=class_id, school=school).exists()
                if not class_exists:
                    return queryset.none()
            if user.role == 'PARENT':
                try:
                    c_id = int(class_id)
                    if c_id not in parent_classes:
                        return queryset.none()
                except (ValueError, TypeError):
                    return queryset.none()
            queryset = queryset.filter(target_class_id=class_id)

        # Filter: Date Ranges on published_at
        from_date = params.get('from_date') or params.get('date_after') or params.get('published_after')
        if from_date:
            queryset = queryset.filter(published_at__date__gte=from_date)

        to_date = params.get('to_date') or params.get('date_before') or params.get('published_before')
        if to_date:
            queryset = queryset.filter(published_at__date__lte=to_date)

        # Filter: is_active
        is_active = params.get('is_active')
        if is_active is not None:
            val = is_active.lower() in ['true', '1', 'yes']
            queryset = queryset.filter(is_active=val)

        return queryset.distinct()

    def perform_create(self, serializer):
        user = self.request.user
        school = attach_user_to_school(user)

        audience_type = serializer.validated_data.get('audience_type', Announcement.AudienceType.SCHOOL)
        target_class = serializer.validated_data.get('target_class')

        if user.role == 'TEACHER':
            if audience_type == Announcement.AudienceType.SCHOOL:
                raise PermissionDenied("Teachers are not permitted to create school-wide announcements. Admin approval is required.")
            if audience_type == Announcement.AudienceType.CLASS:
                if not target_class or not target_class.teachers.filter(id=user.id).exists():
                    raise PermissionDenied("You can only create announcements for classes assigned to you.")

        extra = {'created_by': user}
        if 'is_active' not in serializer.validated_data:
            extra['is_active'] = True

        if user.is_superuser and 'school' in serializer.validated_data:
            instance = serializer.save(**extra)
        else:
            instance = serializer.save(school=school, **extra)

        # Dispatch real-time in-app notifications for target parents
        NotificationService.create_announcement_notifications(instance)
