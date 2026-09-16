from django.urls import path
from .views import (
    ChangePasswordView,
    LoginView,
    UserProfileView,
    SendOTPView,
    VerifyOTPView,
    SchoolStaffDetailView,
    SchoolStaffListView,
    StaffResetPasswordView,
)

urlpatterns = [
    path('login/', LoginView.as_view(), name='auth_login'),
    path('me/', UserProfileView.as_view(), name='auth_me'),
    path('change-password/', ChangePasswordView.as_view(), name='auth_change_password'),

    # Admin-only staff picker (assign teacher to class, link parent to student)
    path('staff/', SchoolStaffListView.as_view(), name='auth_staff_list'),
    path('staff/<int:pk>/', SchoolStaffDetailView.as_view(), name='auth_staff_detail'),
    path(
        'staff/<int:pk>/reset-password/',
        StaffResetPasswordView.as_view(),
        name='auth_staff_reset_password',
    ),
    
    # WhatsApp OTP Authentication Endpoints
    path('otp/send/', SendOTPView.as_view(), name='auth_otp_send'),
    path('otp/verify/', VerifyOTPView.as_view(), name='auth_otp_verify'),
]
