from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .today import ParentTodayView
from .views import (
    ClassViewSet,
    StudentViewSet,
    ParentChildrenView,
    StudentImportView,
)

router = DefaultRouter()
router.register(r'classes', ClassViewSet, basename='class')
router.register(r'students', StudentViewSet, basename='student')

urlpatterns = [
    path('parent/children/', ParentChildrenView.as_view(), name='parent_children'),
    path('parent/today/', ParentTodayView.as_view(), name='parent_today'),
    # Bulk roll onboarding (admin only)
    path('students/import/', StudentImportView.as_view(), name='student_import'),
    path('', include(router.urls)),
]
