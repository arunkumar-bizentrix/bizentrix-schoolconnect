import logging

from django.db.models import Q
from rest_framework import status, permissions, parsers
from rest_framework.pagination import PageNumberPagination
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from apps.notifications.models import DeviceToken
from apps.schools.services import get_school_for

from .models import OTPVerification, User
from .services import (
    AccountError,
    EmailService,
    WhatsAppService,
    create_school_account,
    reset_temporary_password,
)
from .services.accounts import MANAGED_ROLES, normalize_phone, split_name
from .serializers import (
    LoginSerializer,
    StaffCreateSerializer,
    StaffSummarySerializer,
    StaffUpdateSerializer,
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


def _is_school_admin(user):
    return user.is_authenticated and (user.role == User.Role.ADMIN or user.is_superuser)


def _forbidden_unless_admin(user):
    if _is_school_admin(user):
        return None
    return Response(
        {"detail": "Only school administrators can manage teacher and parent accounts."},
        status=status.HTTP_403_FORBIDDEN,
    )


def _people_queryset(user):
    """Teacher and parent accounts this admin manages."""
    queryset = User.objects.filter(role__in=MANAGED_ROLES)
    if not (user.is_superuser and not user.school):
        queryset = queryset.filter(school=get_school_for(user))
    return queryset


def _with_linked(queryset, role):
    related = 'assigned_classes' if role == User.Role.TEACHER else 'children'
    return queryset.prefetch_related(related)


class SchoolStaffListView(APIView):
    """
    GET  /api/v1/auth/staff/?role=TEACHER
        The school's teachers or parents. Backs both the admin's People screen
        and the pickers (assigning a teacher to a class, linking a parent).
        ?search= matches name, phone, email or username.
        ?include_inactive=1 also lists deactivated accounts.
        ?page=N switches to a paginated envelope - a school has a thousand
        parents, and the People screen should not pull all of them at once.

    POST /api/v1/auth/staff/
        Creates a teacher or parent account and returns a one-time password
        for the admin to hand over. Teachers cannot sign themselves up.

    Admin only: ordinary users have no reason to enumerate or create accounts.
    """
    permission_classes = [permissions.IsAuthenticated]
    page_size = 30

    def get(self, request):
        denied = _forbidden_unless_admin(request.user)
        if denied:
            return denied

        role = (request.query_params.get('role') or User.Role.TEACHER).upper()
        if role not in MANAGED_ROLES:
            return Response(
                {"detail": "role must be TEACHER or PARENT."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        queryset = _people_queryset(request.user).filter(role=role)
        if request.query_params.get('include_inactive') not in ('1', 'true', 'True'):
            queryset = queryset.filter(is_active=True)

        search = (request.query_params.get('search') or '').strip()
        if search:
            queryset = queryset.filter(
                Q(first_name__icontains=search)
                | Q(last_name__icontains=search)
                | Q(email__icontains=search)
                | Q(phone_number__icontains=search)
                | Q(username__icontains=search)
            )

        queryset = _with_linked(queryset, role).order_by(
            '-is_active', 'first_name', 'last_name', 'username'
        )

        if 'page' not in request.query_params:
            return Response(StaffSummarySerializer(queryset, many=True).data)

        paginator = PageNumberPagination()
        paginator.page_size = self.page_size
        page = paginator.paginate_queryset(queryset, request, view=self)
        return paginator.get_paginated_response(
            StaffSummarySerializer(page, many=True).data
        )

    def post(self, request):
        denied = _forbidden_unless_admin(request.user)
        if denied:
            return denied

        serializer = StaffCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            user, temporary_password = create_school_account(
                school=get_school_for(request.user),
                role=data['role'],
                full_name=data['full_name'],
                phone_number=data['phone_number'],
                email=data.get('email', ''),
            )
        except AccountError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        logger.info("Admin %s created %s account %s", request.user.pk, user.role, user.pk)
        return Response(
            {
                'account': StaffSummarySerializer(user).data,
                'temporary_password': temporary_password,
            },
            status=status.HTTP_201_CREATED,
        )


class SchoolStaffDetailView(APIView):
    """
    PATCH /api/v1/auth/staff/<id>/
    Edit a teacher or parent: name, phone, email, or deactivate them.

    Accounts are deactivated rather than deleted. A teacher who leaves still
    owns the homework and attendance they recorded, and that history must
    survive them.
    """
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, pk):
        denied = _forbidden_unless_admin(request.user)
        if denied:
            return denied

        person = _people_queryset(request.user).filter(pk=pk).first()
        if person is None:
            return Response({"detail": "Account not found."}, status=status.HTTP_404_NOT_FOUND)

        serializer = StaffUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        if 'phone_number' in data:
            phone = normalize_phone(data['phone_number'])
            if len(phone) != 10:
                return Response(
                    {"detail": "Enter a 10-digit mobile number."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            clash = User.objects.filter(role=person.role, phone_number=phone).exclude(pk=person.pk)
            if clash.exists():
                return Response(
                    {"detail": "Another %s already uses %s." % (person.role.lower(), phone)},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            person.phone_number = phone

        if 'email' in data:
            email = (data['email'] or '').strip().lower()
            if email and User.objects.filter(email__iexact=email).exclude(pk=person.pk).exists():
                return Response(
                    {"detail": "Another account already uses %s." % email},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            person.email = email

        if 'full_name' in data:
            person.first_name, person.last_name = split_name(data['full_name'])

        if 'is_active' in data:
            person.is_active = data['is_active']

        person.save()
        if 'is_active' in data and not person.is_active:
            # A deactivated account must stop receiving pushes at once.
            DeviceToken.objects.filter(user=person).delete()

        person = _with_linked(User.objects, person.role).get(pk=person.pk)
        return Response(StaffSummarySerializer(person).data)


class StaffResetPasswordView(APIView):
    """
    POST /api/v1/auth/staff/<id>/reset-password/
    A teacher or parent forgot their password: issue a new one-time password.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        denied = _forbidden_unless_admin(request.user)
        if denied:
            return denied

        person = _people_queryset(request.user).filter(pk=pk).first()
        if person is None:
            return Response({"detail": "Account not found."}, status=status.HTTP_404_NOT_FOUND)

        temporary_password = reset_temporary_password(person)
        logger.info("Admin %s reset the password of account %s", request.user.pk, person.pk)
        return Response({'temporary_password': temporary_password})


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
