from rest_framework import viewsets, permissions, filters
from .models import Homework
from .serializers import HomeworkSerializer
from .permissions import IsHomeworkAuthorized


class HomeworkViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing Homework with role-based and tenant isolation.
    - List homework: GET /api/v1/homework/
    - Create homework: POST /api/v1/homework/ (Teachers & Admins only)
    - Retrieve homework: GET /api/v1/homework/<id>/
    - Update homework: PUT/PATCH /api/v1/homework/<id>/ (Teachers & Admins only)
    - Delete homework: DELETE /api/v1/homework/<id>/ (Teachers & Admins only)
    """
    serializer_class = HomeworkSerializer
    permission_classes = [permissions.IsAuthenticated, IsHomeworkAuthorized]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['title', 'subject', 'description']
    ordering_fields = ['due_date', 'assigned_date', 'created_at']

    def get_queryset(self):
        user = self.request.user
        if user.is_superuser:
            return Homework.objects.select_related('school', 'classroom', 'assigned_by').all()

        queryset = Homework.objects.select_related(
            'school', 'classroom', 'assigned_by'
        ).filter(school=user.school, is_active=True)

        # Parents only see homework for their children's classes
        if user.role == 'PARENT':
            children_classes = user.children.filter(
                is_active=True,
                class_enrolled__isnull=False,
            ).values_list('class_enrolled_id', flat=True)
            queryset = queryset.filter(classroom_id__in=children_classes)

        # Optional class filtering: ?class_id=1
        class_id = self.request.query_params.get('class_id')
        if class_id:
            queryset = queryset.filter(classroom_id=class_id)

        # Optional subject filtering: ?subject=Mathematics
        subject = self.request.query_params.get('subject')
        if subject:
            queryset = queryset.filter(subject__iexact=subject)

        return queryset

    def perform_create(self, serializer):
        user = self.request.user
        if user.is_superuser and 'school' in serializer.validated_data:
            serializer.save(assigned_by=user)
        else:
            serializer.save(school=user.school, assigned_by=user)
