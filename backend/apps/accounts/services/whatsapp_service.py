import os
import json
import logging
import urllib.request
import urllib.error
from django.conf import settings

logger = logging.getLogger('schoolconnect.whatsapp')


class WhatsAppService:
    """
    Dual-Mode WhatsApp Service for Bizentrix SchoolConnect.

    1. LIVE MODE:
       When WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID are configured in .env,
       dispatches the OTP exclusively via the official Meta WhatsApp Cloud API.
       - NEVER logs access tokens.
       - NEVER prints raw OTP in logs/console.
       - Returns clean structured success/failure dictionaries.

    2. LOCAL DEVELOPMENT MODE:
       When Meta credentials are NOT configured AND settings.DEBUG is True,
       the send is a no-op that reports success. The OTP is NEVER printed or
       logged - look it up in the OTPVerification table if you need it.
    """

    @classmethod
    def get_credentials(cls):
        token = getattr(settings, 'WHATSAPP_ACCESS_TOKEN', None)
        phone_number_id = getattr(settings, 'WHATSAPP_PHONE_NUMBER_ID', None)
        api_version = getattr(settings, 'WHATSAPP_API_VERSION', 'v20.0') or 'v20.0'
        template_name = getattr(settings, 'WHATSAPP_OTP_TEMPLATE', 'hello_world') or 'hello_world'
        return token, phone_number_id, api_version, template_name

    @classmethod
    def is_live_mode(cls) -> bool:
        token, phone_number_id, _, _ = cls.get_credentials()
        return bool(token and phone_number_id)

    @classmethod
    def format_phone_for_whatsapp(cls, phone_number: str) -> str:
        """
        Formats phone number for WhatsApp Cloud API (requires country code without + or dashes).
        Default country is India (+91) if 10 digits provided.
        """
        cleaned = ''.join(ch for ch in str(phone_number) if ch.isdigit())
        if len(cleaned) == 10:
            return f"91{cleaned}"
        elif len(cleaned) == 12 and cleaned.startswith('91'):
            return cleaned
        return cleaned

    @classmethod
    def send_otp(cls, phone_number: str, raw_otp: str) -> dict:
        """
        Sends OTP to recipient phone number.
        Returns:
            {
                "success": bool,
                "mode": "live" | "development",
                "message": str,
                "error": str | None,
                "message_id": str | None,
            }
        """
        token, phone_number_id, api_version, template_name = cls.get_credentials()
        formatted_recipient = cls.format_phone_for_whatsapp(phone_number)

        # ═════════════════════════════════════════════════════════════════════
        # 1. LIVE MODE: Meta WhatsApp Cloud API
        # ═════════════════════════════════════════════════════════════════════
        if token and phone_number_id:
            try:
                url = f"https://graph.facebook.com/{api_version}/{phone_number_id}/messages"
                headers = {
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                }

                # Construct payload based on template configuration
                if template_name == "hello_world":
                    payload = {
                        "messaging_product": "whatsapp",
                        "recipient_type": "individual",
                        "to": formatted_recipient,
                        "type": "template",
                        "template": {
                            "name": "hello_world",
                            "language": {"code": "en_US"},
                        },
                    }
                elif template_name == "text":
                    payload = {
                        "messaging_product": "whatsapp",
                        "recipient_type": "individual",
                        "to": formatted_recipient,
                        "type": "text",
                        "text": {
                            "body": f"Your SchoolConnect login verification code is: {raw_otp}. Valid for 5 minutes.",
                        },
                    }
                else:
                    # Standard Authentication / Utility template with OTP parameter
                    payload = {
                        "messaging_product": "whatsapp",
                        "recipient_type": "individual",
                        "to": formatted_recipient,
                        "type": "template",
                        "template": {
                            "name": template_name,
                            "language": {"code": "en_US"},
                            "components": [
                                {
                                    "type": "body",
                                    "parameters": [
                                        {"type": "text", "text": raw_otp},
                                    ],
                                },
                                {
                                    "type": "button",
                                    "sub_type": "url",
                                    "index": "0",
                                    "parameters": [
                                        {"type": "text", "text": raw_otp},
                                    ],
                                },
                            ],
                        },
                    }

                req = urllib.request.Request(
                    url,
                    data=json.dumps(payload).encode('utf-8'),
                    headers=headers,
                    method='POST',
                )

                with urllib.request.urlopen(req, timeout=12) as response:
                    res_body = response.read().decode('utf-8')
                    res_data = json.loads(res_body)
                    msg_id = res_data.get('messages', [{}])[0].get('id')
                    logger.info(f"Meta WhatsApp OTP dispatched to +{formatted_recipient} (msg_id: {msg_id})")
                    return {
                        "success": True,
                        "mode": "live",
                        "message": "OTP sent via WhatsApp successfully.",
                        "error": None,
                        "message_id": msg_id,
                    }

            except urllib.error.HTTPError as e:
                err_body = e.read().decode('utf-8') if e.fp else str(e)
                try:
                    err_json = json.loads(err_body)
                    error_info = err_json.get('error', {})
                    msg = error_info.get('message', f'HTTP {e.code}')
                    details = error_info.get('error_data', {}).get('details', '')
                    error_display = f"{msg} - {details}".strip(' -')
                except Exception:
                    error_display = f"HTTP {e.code}: {err_body}"

                logger.error(f"Meta WhatsApp Cloud API HTTP Error {e.code}: {error_display}")
                return {
                    "success": False,
                    "mode": "live",
                    "message": "Failed to deliver WhatsApp message via Meta Cloud API.",
                    "error": error_display,
                    "message_id": None,
                }
            except Exception as e:
                logger.error(f"Meta WhatsApp Cloud API Connection Error: {str(e)}")
                return {
                    "success": False,
                    "mode": "live",
                    "message": "Failed to connect to Meta WhatsApp Cloud API.",
                    "error": str(e),
                    "message_id": None,
                }

        # ═════════════════════════════════════════════════════════════════════
        # 2. LOCAL DEVELOPMENT MODE: no delivery, no OTP disclosure
        # ═════════════════════════════════════════════════════════════════════
        if getattr(settings, 'DEBUG', False):
            # Local development has no WhatsApp delivery. The OTP is never
            # printed or logged - retrieve it from the OTPVerification row in
            # the Django admin, or use the email OTP flow instead.
            logger.info(
                "[DEV] WhatsApp OTP generated for +%s (code withheld from logs)",
                formatted_recipient,
            )

            return {
                "success": True,
                "mode": "development",
                "message": "OTP dispatched in development mode.",
                "error": None,
                "message_id": None,
            }

        return {
            "success": False,
            "mode": "development",
            "message": "WhatsApp Cloud API credentials not configured.",
            "error": "Missing WHATSAPP_ACCESS_TOKEN or WHATSAPP_PHONE_NUMBER_ID.",
            "message_id": None,
        }
