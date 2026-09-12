import logging
from rest_framework import status, permissions, parsers
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from .models import OTPVerification
from .services import WhatsAppService, EmailService
from .serializers import (
    LoginSerializer,
    UserSerializer,
    SendOTPSerializer,
    VerifyOTPSerializer,
    SendEmailOTPSerializer,
    VerifyEmailOTPSerializer,
    RegisterSerializer,
)

logger = logging.getLogger('schoolconnect.accounts')


class ThrottledTokenObtainPairView(TokenObtainPairView):
    """
    POST /api/v1/auth/token/
    SimpleJWT's credential endpoint, rate limited per client IP. This is the
    endpoint the mobile app uses for password sign-in.
    """
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'


class ThrottledTokenRefreshView(TokenRefreshView):
    """
    POST /api/v1/auth/token/refresh/
    Rotates the access token. Throttled to stop refresh-token grinding.
    """
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'


class LoginView(APIView):
    """
    POST /api/v1/auth/login/
    Authenticates user and returns JWT access/refresh tokens along with full profile.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data, status=status.HTTP_200_OK)


class UserProfileView(APIView):
    """
    GET /api/v1/auth/me/
    Returns the authenticated user's profile and school details.

    PATCH /api/v1/auth/me/
    Updates user details such as first_name, last_name, phone_number, and profile_picture.
    """
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [parsers.MultiPartParser, parsers.FormParser, parsers.JSONParser]

    def get(self, request):
        serializer = UserSerializer(request.user, context={'request': request})
        return Response(serializer.data, status=status.HTTP_200_OK)

    def patch(self, request):
        serializer = UserSerializer(
            request.user,
            data=request.data,
            partial=True,
            context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data, status=status.HTTP_200_OK)


class SendEmailOTPView(APIView):
    """
    POST /api/v1/auth/otp/email/send/
    Dispatches a cryptographically secure 6-digit OTP via real SMTP email.
    
    Security guarantees:
    - Never prints OTP to terminal.
    - Never logs OTP, tokens, or SMTP credentials.
    - Never returns OTP in the API response.
    - Safe anti-enumeration response structure.
    - 60s cooldown and 10 req/hour rate limiting.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    def post(self, request):
        serializer = SendEmailOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        email = serializer.validated_data['email']
        user = serializer.validated_data.get('user')
        purpose = serializer.validated_data.get('purpose', 'login')

        ip = (
            request.META.get('HTTP_X_FORWARDED_FOR', '').split(',')[0].strip()
            or request.META.get('REMOTE_ADDR')
        )

        # Generate OTP record for the destination email. The record is kept
        # even for unknown/inactive addresses so per-destination rate limits
        # still apply, but the OTP email is ONLY sent to active users or during registration.
        record, raw_otp = OTPVerification.generate_otp(
            destination=email,
            channel=OTPVerification.Channel.EMAIL,
            user=user,
            ip_address=ip,
            validity_minutes=5,
            max_attempts=5,
        )

        if user or purpose == 'register':
            mail_result = EmailService.send_otp_email(email, raw_otp)
            if not mail_result.get('success'):
                logger.error("Failed to send OTP email to recipient.")
                error_detail = mail_result.get('error') or "Email delivery service is currently not configured on this server."
                return Response({
                    'detail': error_detail,
                }, status=status.HTTP_503_SERVICE_UNAVAILABLE)

        # Generic success regardless of account existence (anti-enumeration):
        # unknown/inactive addresses get no email but the same response shape.
        return Response({
            'success': True,
            'status': 'success',
            'detail': f"An OTP has been sent to {email}.",
            'message': f"An OTP has been sent to {email}.",
            'email': email,
            'expires_in_seconds': 300,
        }, status=status.HTTP_200_OK)


class VerifyEmailOTPView(APIView):
    """
    POST /api/v1/auth/otp/email/verify/
    Verifies 6-digit OTP against stored hash and returns SimpleJWT access and refresh tokens.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    def post(self, request):
        serializer = VerifyEmailOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data, status=status.HTTP_200_OK)


class SendOTPView(APIView):
    """
    POST /api/v1/auth/otp/send/
    Dispatches a 6-digit WhatsApp OTP to a registered school user.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    def post(self, request):
        serializer = SendOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone_number = serializer.validated_data['phone_number']

        ip = (
            request.META.get('HTTP_X_FORWARDED_FOR', '').split(',')[0].strip()
            or request.META.get('REMOTE_ADDR')
        )

        record, raw_otp = OTPVerification.generate_otp(
            destination=phone_number,
            channel=OTPVerification.Channel.WHATSAPP,
            ip_address=ip,
        )
        wa_res = WhatsAppService.send_otp(phone_number, raw_otp)

        if not wa_res.get('success'):
            return Response({
                'detail': f"WhatsApp delivery failed: {wa_res.get('error', 'Unable to send message via WhatsApp.')}",
                'whatsapp_error': wa_res.get('error'),
            }, status=status.HTTP_400_BAD_REQUEST)

        response_data = {
            'success': True,
            'status': 'success',
            'message': 'OTP sent via WhatsApp successfully.',
            'phone_number': phone_number,
            'expires_in': 300,
            'expires_in_seconds': 300,
        }

        return Response(response_data, status=status.HTTP_200_OK)


class VerifyOTPView(APIView):
    """
    POST /api/v1/auth/otp/verify/
    Verifies 6-digit OTP and issues SimpleJWT access + refresh tokens and user profile.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    def post(self, request):
        serializer = VerifyOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data, status=status.HTTP_200_OK)


class RegisterView(APIView):
    """
    POST /api/v1/auth/register/
    Registers a new parent or teacher, associates them with Vivekananda School Bagalur,
    dispatches a branded welcome email via real SMTP, and returns JWT auth tokens.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # Dispatch welcome email if recipient email provided
        if user.email:
            full_name = f"{user.first_name} {user.last_name}".strip() or user.username
            EmailService.send_welcome_email(
                recipient_email=user.email,
                full_name=full_name,
                role=user.role,
            )

        refresh = RefreshToken.for_user(user)

        return Response({
            'success': True,
            'status': 'success',
            'message': f"Account registered successfully for {user.first_name or user.username}!",
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': UserSerializer(user, context={'request': request}).data,
        }, status=status.HTTP_201_CREATED)
