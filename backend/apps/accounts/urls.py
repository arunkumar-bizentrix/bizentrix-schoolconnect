from django.urls import path
from .views import (
    LoginView,
    UserProfileView,
    SendOTPView,
    VerifyOTPView,
    SendEmailOTPView,
    VerifyEmailOTPView,
    RegisterView,
)

urlpatterns = [
    path('login/', LoginView.as_view(), name='auth_login'),
    path('register/', RegisterView.as_view(), name='auth_register'),
    path('me/', UserProfileView.as_view(), name='auth_me'),
    
    # Email OTP Authentication Endpoints
    path('otp/email/send/', SendEmailOTPView.as_view(), name='auth_otp_email_send'),
    path('otp/email/verify/', VerifyEmailOTPView.as_view(), name='auth_otp_email_verify'),

    # WhatsApp OTP Authentication Endpoints (Preserved for backwards compatibility)
    path('otp/send/', SendOTPView.as_view(), name='auth_otp_send'),
    path('otp/verify/', VerifyOTPView.as_view(), name='auth_otp_verify'),
]
