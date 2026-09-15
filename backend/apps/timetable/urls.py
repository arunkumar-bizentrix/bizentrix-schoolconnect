from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import SubjectViewSet, TimetableViewSet

router = DefaultRouter()
router.register(r'subjects', SubjectViewSet, basename='subject')
router.register(r'timetable', TimetableViewSet, basename='timetable')

urlpatterns = [
    path('', include(router.urls)),
]
