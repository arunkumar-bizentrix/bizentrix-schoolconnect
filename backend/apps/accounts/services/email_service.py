import logging
from django.conf import settings
from django.core.mail import EmailMultiAlternatives

logger = logging.getLogger('schoolconnect.email')


class EmailService:
    """
    Dedicated Email Delivery Service for Bizentrix SchoolConnect.
    
    Dispatches OTP verification emails exclusively via configured SMTP.
    - Zero console email fallback.
    - Zero OTP or credential logging.
    - Delivers both plain text and clean professional HTML.
    """

    @classmethod
    def is_configured(cls) -> bool:
        """
        Verifies that essential SMTP settings are provided.
        Checks EMAIL_HOST and (unless running tests with in-memory backend) EMAIL_HOST_USER.
        """
        backend = getattr(settings, 'EMAIL_BACKEND', '')
        # Allow Locmem backend during automated tests
        if 'locmem' in backend:
            return True
        host = getattr(settings, 'EMAIL_HOST', '')
        user = getattr(settings, 'EMAIL_HOST_USER', '')
        password = getattr(settings, 'EMAIL_HOST_PASSWORD', '')
        return bool(host and user and password)

    @classmethod
    def send_otp_email(cls, recipient_email: str, raw_otp: str) -> dict:
        """
        Sends the 6-digit login OTP email to recipient.
        Returns:
            {"success": bool, "error": str | None}
        """
        # Strict validation: Check SMTP configuration
        backend = getattr(settings, 'EMAIL_BACKEND', '')
        is_test_mode = 'locmem' in backend

        if not is_test_mode and not cls.is_configured():
            logger.error("SMTP credentials missing in environment variables. Email dispatch aborted.")
            return {
                "success": False,
                "error": "Email delivery service is currently not configured on this server.",
            }

        subject = "Bizentrix SchoolConnect - Login OTP"
        from_email = getattr(settings, 'DEFAULT_FROM_EMAIL', None) or getattr(settings, 'EMAIL_HOST_USER', 'noreply@schoolconnect.edu')

        # Plaintext body (strictly adhering to required format)
        text_content = (
            "Bizentrix SchoolConnect\n\n"
            "Your login verification code is:\n\n"
            f"{raw_otp}\n\n"
            "This OTP is valid for 5 minutes.\n\n"
            "Do not share this OTP with anyone.\n\n"
            "If you did not request this code, you can safely ignore this email.\n\n"
            "Regards,\n"
            "Bizentrix SchoolConnect\n"
        )

        # Professional HTML body
        html_content = f"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{subject}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f1f5f9; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #f1f5f9; padding: 40px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" max-width="520" style="max-width: 520px; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.06); border: 1px solid #e2e8f0;">
          <!-- Header -->
          <tr>
            <td style="background: linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%); padding: 32px 24px; text-align: center;">
              <h1 style="margin: 0; color: #ffffff; font-size: 24px; font-weight: 700; letter-spacing: -0.5px;">Bizentrix SchoolConnect</h1>
              <p style="margin: 6px 0 0 0; color: #bfdbfe; font-size: 14px;">Multi-School Secure Portal</p>
            </td>
          </tr>
          <!-- Body Content -->
          <tr>
            <td style="padding: 36px 32px; color: #334155; line-height: 1.6;">
              <p style="margin: 0 0 16px 0; font-size: 16px; font-weight: 500;">Hello,</p>
              <p style="margin: 0 0 24px 0; font-size: 15px; color: #475569;">
                Your login verification code is:
              </p>
              <!-- OTP Box -->
              <div style="background-color: #f8fafc; border: 2px dashed #93c5fd; border-radius: 12px; padding: 20px; text-align: center; margin: 24px 0;">
                <span style="font-size: 34px; font-weight: 800; color: #1e3a8a; letter-spacing: 8px; font-family: monospace;">{raw_otp}</span>
              </div>
              <p style="margin: 0 0 12px 0; font-size: 14px; color: #64748b; text-align: center;">
                ⏳ This OTP is valid for <strong>5 minutes</strong>.
              </p>
              <div style="margin-top: 24px; padding: 16px; background-color: #fef2f2; border-left: 4px solid #ef4444; border-radius: 6px;">
                <p style="margin: 0; font-size: 13px; color: #991b1b; line-height: 1.5;">
                  <strong>Security Note:</strong> Do not share this OTP with anyone. SchoolConnect staff will never ask for your code.
                </p>
              </div>
              <p style="margin: 24px 0 0 0; font-size: 13px; color: #64748b; line-height: 1.5;">
                If you did not request this code, you can safely ignore this email.
              </p>
              <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 28px 0;">
              <p style="margin: 0; font-size: 14px; color: #334155; font-weight: 600;">
                Regards,<br>
                <span style="color: #2563eb;">Bizentrix SchoolConnect</span>
              </p>
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="background-color: #f8fafc; padding: 20px 32px; text-align: center; border-top: 1px solid #e2e8f0;">
              <p style="margin: 0; font-size: 12px; color: #94a3b8;">
                © Bizentrix SchoolConnect. All rights reserved. Automated security notification.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

        try:
            msg = EmailMultiAlternatives(
                subject=subject,
                body=text_content,
                from_email=from_email,
                to=[recipient_email],
            )
            msg.attach_alternative(html_content, "text/html")
            msg.send(fail_silently=False)
            logger.info("Email OTP dispatched successfully to destination.")
            return {"success": True, "error": None}
        except Exception as exc:
            # Strictly log only generic exception class name, never credentials or raw OTP
            logger.error("Failed to send OTP email: %s", exc.__class__.__name__)
            return {
                "success": False,
                "error": f"Failed to deliver email through SMTP: {exc.__class__.__name__}",
            }

    @classmethod
    def send_welcome_email(cls, recipient_email: str, full_name: str, role: str) -> dict:
        """
        Sends a welcome registration confirmation email to newly registered parents or teachers.
        """
        backend = getattr(settings, 'EMAIL_BACKEND', '')
        is_test_mode = 'locmem' in backend

        if not is_test_mode and not cls.is_configured():
            logger.error("SMTP credentials missing. Welcome email dispatch aborted.")
            return {
                "success": False,
                "error": "Email delivery service is currently not configured.",
            }

        role_label = "Parent / Guardian" if str(role).upper() == 'PARENT' else "Faculty / Teacher"
        subject = "Welcome to Vivekananda School, Bagalur - SchoolConnect"
        from_email = getattr(settings, 'DEFAULT_FROM_EMAIL', None) or getattr(settings, 'EMAIL_HOST_USER', 'noreply@schoolconnect.edu')

        text_content = (
            f"Dear {full_name},\n\n"
            f"Welcome to Vivekananda School, Bagalur - SchoolConnect Portal!\n\n"
            f"Your {role_label} account has been successfully created.\n\n"
            "You can now track daily homework, view academic circulars, and receive real-time school notifications.\n\n"
            "Institution: Vivekananda School, Bagalur\n"
            "Campus: Jogikalasanapalli, Bagalur, Tamil Nadu 635103\n"
            "Helpline: +91 94439 40772\n\n"
            "Regards,\n"
            "Vivekananda School Administration & Bizentrix SchoolConnect\n"
        )

        html_content = f"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{subject}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f1f5f9; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #f1f5f9; padding: 40px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 540px; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.06); border: 1px solid #e2e8f0;">
          <tr>
            <td style="background: linear-gradient(135deg, #0f2b5c 0%, #1d4ed8 100%); padding: 32px 24px; text-align: center;">
              <h1 style="margin: 0; color: #ffffff; font-size: 22px; font-weight: 800; letter-spacing: -0.5px;">Vivekananda School, Bagalur</h1>
              <p style="margin: 6px 0 0 0; color: #bfdbfe; font-size: 13.5px;">Official SchoolConnect Portal • Affiliation No: 1930827</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 32px; color: #334155; line-height: 1.6;">
              <h2 style="margin: 0 0 12px 0; font-size: 18px; color: #0f172a;">Welcome, {full_name}! 👋</h2>
              <p style="margin: 0 0 16px 0; font-size: 14px; color: #475569;">
                Your <strong>{role_label}</strong> account has been successfully registered on the Vivekananda SchoolConnect academic platform.
              </p>
              
              <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 12px; padding: 16px; margin: 20px 0;">
                <div style="font-size: 12px; font-weight: 700; color: #2563eb; text-transform: uppercase; margin-bottom: 8px;">Account Overview</div>
                <div style="font-size: 13px; color: #334155; margin-bottom: 4px;"><strong>Registered Role:</strong> {role_label}</div>
                <div style="font-size: 13px; color: #334155; margin-bottom: 4px;"><strong>Email:</strong> {recipient_email}</div>
                <div style="font-size: 13px; color: #334155;"><strong>Institution:</strong> Vivekananda School, Bagalur (VIV001)</div>
              </div>

              <p style="margin: 0 0 12px 0; font-size: 14px; color: #475569;">
                With this account, you can:
              </p>
              <ul style="margin: 0 0 20px 0; padding-left: 20px; font-size: 13.5px; color: #475569; line-height: 1.7;">
                <li>Track and monitor daily homework & assignment deadlines</li>
                <li>Access official school circulars and urgent notices</li>
                <li>Stay connected with subject teachers and faculty members</li>
              </ul>

              <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 24px 0;">
              <p style="margin: 0; font-size: 13px; color: #64748b;">
                Need help or have questions? Contact our school office at <strong>+91 94439 40772</strong> or reply to this email.
              </p>
              <p style="margin: 16px 0 0 0; font-size: 13.5px; color: #0f172a; font-weight: 700;">
                Warm Regards,<br>
                <span style="color: #2563eb;">Vivekananda School Administration</span>
              </p>
            </td>
          </tr>
          <tr>
            <td style="background-color: #f8fafc; padding: 16px 32px; text-align: center; border-top: 1px solid #e2e8f0;">
              <p style="margin: 0; font-size: 11.5px; color: #94a3b8;">
                Jogikalasanapalli, Bagalur, Tamil Nadu 635103 • Vivekananda School, Bagalur
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""
        try:
            msg = EmailMultiAlternatives(
                subject=subject,
                body=text_content,
                from_email=from_email,
                to=[recipient_email],
            )
            msg.attach_alternative(html_content, "text/html")
            msg.send(fail_silently=False)
            logger.info("Welcome email sent successfully to %s", recipient_email)
            return {"success": True, "error": None}
        except Exception as exc:
            logger.error("Failed to send welcome email: %s", exc.__class__.__name__)
            return {
                "success": False,
                "error": f"Failed to deliver welcome email: {exc.__class__.__name__}",
            }

