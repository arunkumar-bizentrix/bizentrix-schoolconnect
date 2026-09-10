from django.conf import settings
from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    class Role(models.TextChoices):
        ADMIN = 'ADMIN', 'Admin'
        TEACHER = 'TEACHER', 'Teacher'
        PARENT = 'PARENT', 'Parent'

    role = models.CharField(
        max_length=20,
        choices=Role.choices,
        default=Role.PARENT,
        help_text="Role determining user permissions and dashboard view",
    )
    school = models.ForeignKey(
        'schools.School',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='users',
        help_text="Tenant association for strict multi-school data isolation",
    )
    phone_number = models.CharField(
        max_length=20,
        blank=True,
        null=True,
        help_text="Contact number for SMS/WhatsApp notifications",
    )
    profile_picture = models.FileField(
        upload_to='profile_pictures/',
        null=True,
        blank=True,
        help_text="User profile picture or avatar image",
    )

    class Meta:
        ordering = ['username']
        verbose_name = 'User'
        verbose_name_plural = 'Users'

    def __str__(self):
        return f"{self.username} [{self.get_role_display()}]"


class OTPVerification(models.Model):
    class Channel(models.TextChoices):
        EMAIL = 'EMAIL', 'Email'
        WHATSAPP = 'WHATSAPP', 'WhatsApp'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='otp_verifications',
        null=True,
        blank=True,
        help_text="Associated user account (if identified)",
    )
    destination = models.CharField(
        max_length=255,
        db_index=True,
        help_text="Standardized recipient email address or phone number",
    )
    channel = models.CharField(
        max_length=20,
        choices=Channel.choices,
        default=Channel.EMAIL,
        db_index=True,
        help_text="Delivery channel (EMAIL or WHATSAPP)",
    )
    otp_hash = models.CharField(
        max_length=128,
        help_text="Cryptographically salted SHA-256 hash of the 6-digit OTP",
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    expires_at = models.DateTimeField(db_index=True)
    is_used = models.BooleanField(default=False, db_index=True)
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveIntegerField(default=0)
    max_attempts = models.PositiveIntegerField(default=5)
    ip_address = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['destination', 'channel', 'is_used', 'expires_at']),
        ]
        verbose_name = 'OTP Verification'
        verbose_name_plural = 'OTP Verifications'

    def __str__(self):
        status = "Used" if self.is_used else ("Expired" if self.is_expired() else "Active")
        return f"[{self.channel}] OTP for {self.destination} ({status}) - Attempts: {self.attempts}/{self.max_attempts}"

    def is_expired(self):
        from django.utils import timezone
        return timezone.now() > self.expires_at

    def verify_code(self, candidate_otp: str) -> bool:
        """
        Verifies candidate OTP against stored hash using constant-time comparison.
        Increments attempts on failure. Enforces max_attempts. Marks as used on success.
        """
        import hashlib
        import hmac
        from django.utils import timezone

        if self.is_used or self.is_expired() or self.attempts >= self.max_attempts:
            return False

        clean_otp = str(candidate_otp).strip()
        candidate_hash = hashlib.sha256(
            f"{self.destination.lower()}:{clean_otp}".encode()
        ).hexdigest()
        fallback_hash = hashlib.sha256(
            f"{self.destination}:{clean_otp}".encode()
        ).hexdigest()

        if hmac.compare_digest(self.otp_hash, candidate_hash) or hmac.compare_digest(self.otp_hash, fallback_hash):
            self.is_used = True
            self.used_at = timezone.now()
            self.save(update_fields=['is_used', 'used_at'])
            return True
        else:
            self.attempts += 1
            self.save(update_fields=['attempts'])
            return False

    @classmethod
    def generate_otp(
        cls,
        destination: str,
        channel: str = None,
        user=None,
        ip_address: str = None,
        validity_minutes: int = 5,
        max_attempts: int = 5,
    ) -> tuple['OTPVerification', str]:
        """
        Invalidates existing active unused OTPs for this destination and channel,
        generates cryptographically secure 6-digit OTP, stores only the hash.
        Returns (record, raw_otp).
        """
        import secrets
        import hashlib
        from datetime import timedelta
        from django.utils import timezone

        now = timezone.now()
        clean_dest = str(destination).strip()
        if channel is None:
            channel = cls.Channel.EMAIL if '@' in clean_dest else cls.Channel.WHATSAPP

        if channel == cls.Channel.EMAIL:
            clean_dest = clean_dest.lower()

        # Invalidate previous unused OTPs for this destination and channel.
        # Wind expires_at 1s into the past so is_expired() is reliable even
        # when the clock tick is the same as `now` (coarse OS timers).
        cls.objects.filter(
            destination=clean_dest,
            channel=channel,
            is_used=False,
            expires_at__gt=now,
        ).update(is_used=False, expires_at=now - timedelta(seconds=1))

        # Cryptographically secure 6-digit OTP (100000 to 999999)
        raw_otp = f"{secrets.randbelow(900000) + 100000}"
        otp_hash = hashlib.sha256(f"{clean_dest}:{raw_otp}".encode()).hexdigest()

        record = cls.objects.create(
            user=user,
            destination=clean_dest,
            channel=channel,
            otp_hash=otp_hash,
            expires_at=now + timedelta(minutes=validity_minutes),
            max_attempts=max_attempts,
            attempts=0,
            is_used=False,
            ip_address=ip_address,
        )
        return record, raw_otp

    # Legacy properties for backward compatibility
    @property
    def phone_number(self):
        return self.destination

    @phone_number.setter
    def phone_number(self, val):
        self.destination = val

    @property
    def otp_code(self):
        return self.otp_hash

    @otp_code.setter
    def otp_code(self, val):
        self.otp_hash = val

    @property
    def is_verified(self):
        return self.is_used

    @is_verified.setter
    def is_verified(self, val):
        self.is_used = val
