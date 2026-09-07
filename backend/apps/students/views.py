from rest_framework import viewsets, permissions, filters
from .models import Class, Student
from .serializers import ClassSerializer, StudentSerializer
from .permissions import IsSchoolMember


class ClassViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing academic Classes with tenant isolation.
    - List classes: GET /api/v1/classes/
    - Create class: POST /api/v1/classes/
    - Retrieve class: GET /api/v1/classes/<id>/
    - Update class: PUT/PATCH /api/v1/classes/<id>/
    """
    serializer_class = ClassSerializer
    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['name', 'section', 'academic_year']
    ordering_fields = ['name', 'section', 'created_at']

    def get_queryset(self):
        user = self.request.user
        if user.is_superuser:
            return Class.objects.select_related('school').all()
        return Class.objects.select_related('school').filter(school=user.school)

    def perform_create(self, serializer):
        user = self.request.user
        if user.is_superuser and 'school' in serializer.validated_data:
            serializer.save()
        else:
            serializer.save(school=user.school)


class StudentViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing Students with tenant isolation.
    - List students: GET /api/v1/students/
    - Create student: POST /api/v1/students/
    - Retrieve student: GET /api/v1/students/<id>/
    - Update student: PUT/PATCH /api/v1/students/<id>/
    """
    serializer_class = StudentSerializer
    permission_classes = [permissions.IsAuthenticated, IsSchoolMember]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['admission_number', 'first_name', 'last_name']
    ordering_fields = ['admission_number', 'first_name', 'created_at']

    def get_queryset(self):
        user = self.request.user
        if user.is_superuser:
            queryset = Student.objects.select_related('school', 'class_enrolled').all()
        else:
            queryset = Student.objects.select_related('school', 'class_enrolled').filter(school=user.school)

        # Optional class filtering: /api/v1/students/?class_id=1
        class_id = self.request.query_params.get('class_id')
        if class_id:
            queryset = queryset.filter(class_enrolled_id=class_id)

        return queryset

    def perform_create(self, serializer):
        user = self.request.user
        if user.is_superuser and 'school' in serializer.validated_data:
            serializer.save()
        else:
            serializer.save(school=user.school)
