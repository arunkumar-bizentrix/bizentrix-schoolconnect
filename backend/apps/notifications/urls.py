from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import DeviceRegistrationView, NotificationViewSet

router = DefaultRouter()
router.register(r'notifications', NotificationViewSet, basename='notification')

urlpatterns = [
    # Push device registration (app registers on sign-in, removes on sign-out)
    path(
        'notifications/register-device/',
        DeviceRegistrationView.as_view(),
        name='notification_register_device',
    ),
    path('', include(router.urls)),
]
