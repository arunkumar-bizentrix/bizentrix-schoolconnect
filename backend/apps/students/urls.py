from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .monitoring import ClassOverviewView, DashboardSummaryView, StudentProfileView, TeacherProfileView
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
    path('dashboard/summary/', DashboardSummaryView.as_view(), name='dashboard_summary'),
    path('students/<int:pk>/profile/', StudentProfileView.as_view(), name='student_profile'),
    path('classes/<int:pk>/overview/', ClassOverviewView.as_view(), name='class_overview'),
    path('auth/staff/<int:pk>/profile/', TeacherProfileView.as_view(), name='teacher_profile'),
    # Bulk roll onboarding (admin only)
    path('students/import/', StudentImportView.as_view(), name='student_import'),
    path('', include(router.urls)),
]
