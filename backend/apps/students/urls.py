from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ClassViewSet, StudentViewSet, ParentChildrenView

router = DefaultRouter()
router.register(r'classes', ClassViewSet, basename='class')
router.register(r'students', StudentViewSet, basename='student')

urlpatterns = [
    path('parent/children/', ParentChildrenView.as_view(), name='parent_children'),
    path('', include(router.urls)),
]
