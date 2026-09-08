from django.urls import path
from .views import LoginView, UserProfileView

urlpatterns = [
    path('login/', LoginView.as_view(), name='auth_login'),
    path('me/', UserProfileView.as_view(), name='auth_me'),
]
