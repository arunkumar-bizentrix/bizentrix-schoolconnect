"""
URL configuration for Bizentrix SchoolConnect project.
"""

from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import path, include
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
)

urlpatterns = [
    path('admin/', admin.site.urls),

    # JWT Authentication Endpoints
    path('api/v1/auth/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/v1/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    # Academic Classes & Students Endpoints
    path('api/v1/', include('apps.students.urls')),

    # Homework Management Endpoints
    path('api/v1/', include('apps.homework.urls')),

    # Announcements & Circulars Endpoints
    path('api/v1/', include('apps.announcements.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
