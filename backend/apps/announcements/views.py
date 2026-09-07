from django.db.models import Q
from rest_framework import viewsets, permissions, filters
from .models import Announcement
from .serializers import AnnouncementSerializer
from .permissions import IsAnnouncementAuthorized


class AnnouncementViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing School Announcements & Circulars with tenant isolation.
    - List announcements: GET /api/v1/announcements/
    - Create announcement: POST /api/v1/announcements/ (Admins & Teachers only)
    - Retrieve announcement: GET /api/v1/announcements/<id>/
    - Update announcement: PUT/PATCH /api/v1/announcements/<id>/ (Admins & Teachers only)
    - Delete announcement: DELETE /api/v1/announcements/<id>/ (Admins & Teachers only)
    """
    serializer_class = AnnouncementSerializer
    permission_classes = [permissions.IsAuthenticated, IsAnnouncementAuthorized]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['title', 'content']
    ordering_fields = ['published_at', 'priority', 'created_at']

    def get_queryset(self):
        user = self.request.user
        if user.is_superuser:
            return Announcement.objects.select_related('school', 'target_class', 'created_by').all()

        queryset = Announcement.objects.select_related(
            'school', 'target_class', 'created_by'
        ).filter(school=user.school, is_active=True)

        # Parents see all SCHOOL announcements and CLASS announcements for their children's classes
        if user.role == 'PARENT':
            parent_classes = user.children.filter(
                is_active=True,
                class_enrolled__isnull=False,
            ).values_list('class_enrolled_id', flat=True)

            queryset = queryset.filter(
                Q(audience_type=Announcement.AudienceType.SCHOOL) |
                Q(audience_type=Announcement.AudienceType.CLASS, target_class_id__in=parent_classes)
            )

        # Optional filter: ?priority=URGENT
        priority = self.request.query_params.get('priority')
        if priority:
            queryset = queryset.filter(priority=priority.upper())

        # Optional filter: ?audience_type=SCHOOL
        audience_type = self.request.query_params.get('audience_type')
        if audience_type:
            queryset = queryset.filter(audience_type=audience_type.upper())

        # Optional filter: ?class_id=1
        class_id = self.request.query_params.get('class_id')
        if class_id:
            queryset = queryset.filter(target_class_id=class_id)

        return queryset

    def perform_create(self, serializer):
        user = self.request.user
        if user.is_superuser and 'school' in serializer.validated_data:
            serializer.save(created_by=user)
        else:
            serializer.save(school=user.school, created_by=user)
