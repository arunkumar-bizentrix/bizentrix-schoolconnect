# Generated manually for channel-independent OTP refactoring

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


def mark_existing_otps_as_whatsapp(apps, schema_editor):
    OTPVerification = apps.get_model('accounts', 'OTPVerification')
    # All existing OTPs in the DB were created via WhatsApp
    OTPVerification.objects.all().update(channel='WHATSAPP')


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('accounts', '0002_otpverification'),
    ]

    operations = [
        # 1. Remove old index before renaming fields
        migrations.RemoveIndex(
            model_name='otpverification',
            name='accounts_ot_phone_n_fcdfde_idx',
        ),
        # 2. Rename phone_number -> destination
        migrations.RenameField(
            model_name='otpverification',
            old_name='phone_number',
            new_name='destination',
        ),
        # 3. Alter destination to max_length=255 for emails
        migrations.AlterField(
            model_name='otpverification',
            name='destination',
            field=models.CharField(db_index=True, help_text='Standardized recipient email address or phone number', max_length=255),
        ),
        # 4. Rename otp_code -> otp_hash
        migrations.RenameField(
            model_name='otpverification',
            old_name='otp_code',
            new_name='otp_hash',
        ),
        # 5. Rename is_verified -> is_used
        migrations.RenameField(
            model_name='otpverification',
            old_name='is_verified',
            new_name='is_used',
        ),
        # 6. Add channel field (default EMAIL, existing rows will be updated to WHATSAPP)
        migrations.AddField(
            model_name='otpverification',
            name='channel',
            field=models.CharField(choices=[('EMAIL', 'Email'), ('WHATSAPP', 'WhatsApp')], db_index=True, default='EMAIL', help_text='Delivery channel (EMAIL or WHATSAPP)', max_length=20),
        ),
        # 7. Add user FK
        migrations.AddField(
            model_name='otpverification',
            name='user',
            field=models.ForeignKey(blank=True, help_text='Associated user account (if identified)', null=True, on_delete=django.db.models.deletion.CASCADE, related_name='otp_verifications', to=settings.AUTH_USER_MODEL),
        ),
        # 8. Add used_at
        migrations.AddField(
            model_name='otpverification',
            name='used_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        # 9. Add max_attempts
        migrations.AddField(
            model_name='otpverification',
            name='max_attempts',
            field=models.PositiveIntegerField(default=5),
        ),
        # 10. Update existing records to WHATSAPP channel
        migrations.RunPython(
            mark_existing_otps_as_whatsapp,
            reverse_code=migrations.RunPython.noop,
        ),
        # 11. Add new compound index
        migrations.AddIndex(
            model_name='otpverification',
            index=models.Index(fields=['destination', 'channel', 'is_used', 'expires_at'], name='accounts_ot_dest_idx'),
        ),
    ]
