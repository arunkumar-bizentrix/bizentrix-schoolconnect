from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import ExamPaperViewSet, ExamViewSet, ReportCardView

router = DefaultRouter()
router.register(r'exams', ExamViewSet, basename='exam')
router.register(r'exam-papers', ExamPaperViewSet, basename='exam-paper')

urlpatterns = [
    path('report-card/', ReportCardView.as_view(), name='report_card'),
    path('', include(router.urls)),
]
