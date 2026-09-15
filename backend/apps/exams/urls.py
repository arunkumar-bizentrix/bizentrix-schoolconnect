from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import ExamPaperViewSet, ExamViewSet, GradeScaleView, ReportCardPdfView, ReportCardView

router = DefaultRouter()
router.register(r'exams', ExamViewSet, basename='exam')
router.register(r'exam-papers', ExamPaperViewSet, basename='exam-paper')

urlpatterns = [
    path('report-card/', ReportCardView.as_view(), name='report_card'),
    path('report-card/pdf/', ReportCardPdfView.as_view(), name='report_card_pdf'),
    path('grade-scale/', GradeScaleView.as_view(), name='grade_scale'),
    path('', include(router.urls)),
]
