import re
from datetime import timedelta
from django.contrib.auth import authenticate
from django.utils import timezone
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken
from apps.schools.models import School
from .models import User, OTPVerification


class SchoolSummarySerializer(serializers.ModelSerializer):
    class Meta:
        model = School
        fields = ['id', 'name', 'code', 'contact_phone']


class UserSerializer(serializers.ModelSerializer):
    school = SchoolSummarySerializer(read_only=True)
    school_name = serializers.CharField(source='school.name', read_only=True, default='')
    school_code = serializers.CharField(source='school.code', read_only=True, default='')
    full_name = serializers.SerializerMethodField()
    profile_picture_url = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id',
            'username',
            'email',
            'first_name',
            'last_name',
            'full_name',
            'role',
            'school',
            'school_name',
            'school_code',
            'phone_number',
            'profile_picture',
            'profile_picture_url',
            'is_active',
        ]
        read_only_fields = ['id', 'username', 'role', 'school', 'is_active']

    def get_full_name(self, obj):
        name = f"{obj.first_name} {obj.last_name}".strip()
        return name or obj.username

    def get_profile_picture_url(self, obj):
        if not obj.profile_picture:
            return None
        request = self.context.get('request')
        if request:
            return request.build_absolute_uri(obj.profile_picture.url)
        return obj.profile_picture.url

    def update(self, instance, validated_data):
        if 'full_name' in self.initial_data:
            full_name = str(self.initial_data['full_name']).strip()
            if full_name:
                parts = full_name.split(' ', 1)
                instance.first_name = parts[0]
                instance.last_name = parts[1] if len(parts) > 1 else ''
        return super().update(instance, validated_data)


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField(required=True)
    password = serializers.CharField(required=True, write_only=True)

    def validate(self, attrs):
        username = attrs.get('username')
        password = attrs.get('password')

        user = authenticate(username=username, password=password)
        if not user:
            raise serializers.ValidationError("Invalid username or password.")

        if not user.is_active:
            raise serializers.ValidationError("User account is disabled.")

        if not user.school and not user.is_superuser:
            user.school = School.objects.first()
            user.save(update_fields=['school'])

        refresh = RefreshToken.for_user(user)

        return {
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': UserSerializer(user).data,
        }


def normalize_phone_number(phone: str) -> str:
    """Normalizes phone number to 10-digit Indian format or standard digits."""
    if not phone:
        return ''
    cleaned = ''.join(ch for ch in str(phone) if ch.isdigit())
    if len(cleaned) == 12 and cleaned.startswith('91'):
        cleaned = cleaned[2:]
    return cleaned


class SendOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(required=True)
    purpose = serializers.CharField(required=False, default='login')

    def validate(self, attrs):
        value = attrs.get('phone_number')
        purpose = attrs.get('purpose', 'login')
        normalized = normalize_phone_number(value)
        if len(normalized) < 10:
            raise serializers.ValidationError({"phone_number": "Please enter a valid 10-digit mobile number."})

        # Only enforce existing user check if NOT registering
        if purpose != 'register':
            user = User.objects.filter(
                phone_number__in=[normalized, f"+91{normalized}", f"91{normalized}"]
            ).first()

            if not user:
                raise serializers.ValidationError({"phone_number": "This phone number is not registered with a school."})

            if not user.is_active:
                raise serializers.ValidationError({"phone_number": "This user account has been deactivated."})

        # Rate limiting: 60-second resend cooldown
        recent_otp = OTPVerification.objects.filter(
            destination=normalized,
            channel=OTPVerification.Channel.WHATSAPP,
            created_at__gte=timezone.now() - timedelta(seconds=60),
        ).first()

        if recent_otp:
            elapsed = (timezone.now() - recent_otp.created_at).total_seconds()
            remaining = max(1, int(60 - elapsed))
            raise serializers.ValidationError({
                "phone_number": f"Please wait {remaining} seconds before requesting another OTP."
            })

        # Rate limiting: Max 10 requests per hour per phone
        hourly_count = OTPVerification.objects.filter(
            destination=normalized,
            channel=OTPVerification.Channel.WHATSAPP,
            created_at__gte=timezone.now() - timedelta(hours=1),
        ).count()

        if hourly_count >= 10:
            raise serializers.ValidationError({"phone_number": "Too many OTP requests. Please try again in an hour."})

        attrs['phone_number'] = normalized
        return attrs


class VerifyOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(required=True)
    otp = serializers.CharField(required=True, min_length=6, max_length=6)

    def validate(self, attrs):
        normalized = normalize_phone_number(attrs.get('phone_number'))
        candidate_otp = attrs.get('otp', '').strip()

        if not candidate_otp.isdigit() or len(candidate_otp) != 6:
            raise serializers.ValidationError({'otp': "OTP must be a 6-digit number."})

        # Retrieve latest unverified OTP record (id tie-breaker keeps this
        # deterministic when two records share the same created_at tick)
        record = OTPVerification.objects.filter(
            destination=normalized,
            channel=OTPVerification.Channel.WHATSAPP,
            is_used=False,
        ).order_by('-created_at', '-id').first()

        if not record:
            raise serializers.ValidationError(
                {'otp': "No active OTP request found for this mobile number. Please request a new OTP."}
            )

        if record.is_expired():
            raise serializers.ValidationError(
                {'otp': "OTP code has expired. Please request a new OTP."}
            )

        if record.attempts >= record.max_attempts:
            raise serializers.ValidationError(
                {'otp': "Maximum verification attempts exceeded. Please request a new OTP."}
            )

        if not record.verify_code(candidate_otp):
            remaining = record.max_attempts - record.attempts
            if remaining <= 0:
                raise serializers.ValidationError(
                    {'otp': "Maximum verification attempts exceeded. Please request a new OTP."}
                )
            raise serializers.ValidationError(
                {'otp': f"Invalid OTP code. {remaining} attempt(s) remaining."}
            )

        # Find user
        user = User.objects.filter(
            phone_number__in=[normalized, f"+91{normalized}", f"91{normalized}"]
        ).first()

        if not user or not user.is_active:
            raise serializers.ValidationError(
                {'phone_number': "This user account is not active or not registered with a school."}
            )

        if not user.school and not user.is_superuser:
            user.school = School.objects.first()
            user.save(update_fields=['school'])

        refresh = RefreshToken.for_user(user)

        return {
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': UserSerializer(user).data,
        }


class SendEmailOTPSerializer(serializers.Serializer):
    """
    Serializer for POST /api/v1/auth/otp/email/send/
    Validates email format, normalizes email, checks cooldown and hourly rate limits.
    Protects against user enumeration.
    """
    email = serializers.EmailField(required=True)
    purpose = serializers.CharField(required=False, default='login')

    def validate(self, attrs):
        raw_email = attrs.get('email', '')
        normalized = raw_email.strip().lower()

        if not normalized:
            raise serializers.ValidationError({"email": "Please enter a valid email address."})

        user = User.objects.filter(email__iexact=normalized, is_active=True).first()

        # Rate limiting: 60-second resend cooldown for this destination
        recent_otp = OTPVerification.objects.filter(
            destination=normalized,
            channel=OTPVerification.Channel.EMAIL,
            created_at__gte=timezone.now() - timedelta(seconds=60),
        ).first()

        if recent_otp:
            elapsed = (timezone.now() - recent_otp.created_at).total_seconds()
            remaining = max(1, int(60 - elapsed))
            raise serializers.ValidationError({
                "detail": f"Please wait {remaining} seconds before requesting another OTP."
            })

        # Rate limiting: Max 10 requests per hour per email
        hourly_count = OTPVerification.objects.filter(
            destination=normalized,
            channel=OTPVerification.Channel.EMAIL,
            created_at__gte=timezone.now() - timedelta(hours=1),
        ).count()

        if hourly_count >= 10:
            raise serializers.ValidationError({
                "detail": "Too many OTP requests. Please try again in an hour."
            })

        attrs['email'] = normalized
        attrs['user'] = user  # May be None if account does not exist (for anti-enumeration)
        attrs['purpose'] = attrs.get('purpose', 'login')
        return attrs


class VerifyEmailOTPSerializer(serializers.Serializer):
    """
    Serializer for POST /api/v1/auth/otp/email/verify/
    Validates 6-digit candidate OTP against stored hash using constant-time comparison,
    enforces 5-minute expiry, max 5 attempts, single-use, and returns SimpleJWT tokens.
    """
    email = serializers.EmailField(required=True)
    otp = serializers.CharField(required=True, min_length=6, max_length=6)

    def validate(self, attrs):
        normalized = attrs.get('email', '').strip().lower()
        candidate_otp = attrs.get('otp', '').strip()

        if not candidate_otp.isdigit() or len(candidate_otp) != 6:
            raise serializers.ValidationError({'otp': "OTP must be a 6-digit number."})

        # Retrieve latest unused email OTP record (id tie-breaker for equal
        # created_at timestamps)
        record = OTPVerification.objects.filter(
            destination=normalized,
            channel=OTPVerification.Channel.EMAIL,
            is_used=False,
        ).order_by('-created_at', '-id').first()

        if not record:
            raise serializers.ValidationError(
                {'otp': "No active OTP request found for this email address. Please request a new OTP."}
            )

        if record.is_expired():
            raise serializers.ValidationError(
                {'otp': "This OTP has expired. Please request a new OTP."}
            )

        if record.attempts >= record.max_attempts:
            raise serializers.ValidationError(
                {'otp': "Too many attempts. Please request a new OTP."}
            )

        if not record.verify_code(candidate_otp):
            remaining = record.max_attempts - record.attempts
            if remaining <= 0:
                raise serializers.ValidationError(
                    {'otp': "Too many attempts. Please request a new OTP."}
                )
            raise serializers.ValidationError(
                {'otp': "Incorrect OTP. Please try again."}
            )

        # Resolve active user
        user = record.user
        if not user:
            user = User.objects.filter(email__iexact=normalized, is_active=True).first()

        if not user:
            return {
                'success': True,
                'status': 'success',
                'verified': True,
                'email': normalized,
                'is_new_user': True,
                'message': "Email verified successfully! You can now complete registration.",
            }

        if not user.is_active:
            raise serializers.ValidationError(
                {'email': "This user account is deactivated."}
            )

        if not user.school and not user.is_superuser:
            user.school = School.objects.first()
            user.save(update_fields=['school'])

        refresh = RefreshToken.for_user(user)

        return {
            'success': True,
            'status': 'success',
            'verified': True,
            'is_new_user': False,
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': UserSerializer(user).data,
        }


class RegisterSerializer(serializers.Serializer):
    """
    Serializer for public Parent / Teacher registration.
    Associates the new user with Vivekananda School Bagalur by default.
    """
    full_name = serializers.CharField(required=True, min_length=2, max_length=150)
    password = serializers.CharField(required=True, min_length=8, write_only=True)
    email = serializers.EmailField(required=False, allow_blank=True, default='')
    phone_number = serializers.CharField(required=False, allow_blank=True, default='')
    role = serializers.CharField(required=False, default='PARENT')
    school_id = serializers.IntegerField(required=False, allow_null=True)

    def validate_role(self, value):
        normalized = str(value).upper().strip()
        if normalized not in [User.Role.PARENT, User.Role.TEACHER]:
            return User.Role.PARENT
        return normalized

    def validate_email(self, value):
        if value:
            normalized = value.strip().lower()
            if User.objects.filter(email__iexact=normalized).exists():
                raise serializers.ValidationError("An account with this email address already exists. Please sign in instead.")
            return normalized
        return ''

    def validate_phone_number(self, value):
        if value:
            return normalize_phone_number(value)
        return ''

    def create(self, validated_data):
        full_name = validated_data['full_name'].strip()
        parts = full_name.split(' ', 1)
        first_name = parts[0]
        last_name = parts[1] if len(parts) > 1 else ''

        email = validated_data.get('email', '').strip().lower()
        phone_number = validated_data.get('phone_number', '')
        password = validated_data['password']
        role = validated_data.get('role', User.Role.PARENT)
        school_id = validated_data.get('school_id')

        school = None
        if school_id:
            school = School.objects.filter(id=school_id).first()
        if not school:
            school = School.objects.first()

        # Generate clean, unique username
        if email:
            base_username = email.split('@')[0]
        elif phone_number:
            base_username = f"user_{phone_number}"
        else:
            base_username = full_name.lower()

        base_username = re.sub(r'[^a-zA-Z0-9_]', '', base_username.replace(' ', '_'))
        if not base_username:
            base_username = "user"

        username = base_username
        counter = 1
        while User.objects.filter(username=username).exists():
            username = f"{base_username}_{counter}"
            counter += 1

        user = User.objects.create_user(
            username=username,
            email=email,
            password=password,
            first_name=first_name,
            last_name=last_name,
            role=role,
            phone_number=phone_number,
            school=school,
            is_active=True,
        )
        return user
