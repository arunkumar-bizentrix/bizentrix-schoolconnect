# SMS for temporary passwords

When the admin creates a teacher or parent, or resets a password, the backend
generates a temporary password. With SMS configured it is texted to the
person's mobile number and **never shown or returned anywhere else**. Without
SMS, the admin sees it once, marked *Not sent by SMS*, and hands it over.

**Status today: SMS is not configured.** No provider is integrated yet, by
decision, so nothing is sent and nothing is faked.

## How it behaves

| Situation | What the admin sees | API response |
|---|---|---|
| SMS configured and sent | "Sent by SMS to 98xxxxxxxx" | `delivery: "sms"`, **no** `temporary_password` |
| `SMS_PROVIDER` empty | Password once, "Not sent by SMS - SMS is not set up" | `delivery: "shown_to_admin"`, `sms_status: "not_configured"` |
| Provider set but unknown to this version | Same, with that reason | `sms_status: "not_configured"` |
| Provider error / timeout | Same, with the error class | `sms_status: "failed"` |

Whatever happens with SMS, the account is created, and the password is never
written to logs, notifications or the database (only its hash is stored).

## Security rules that apply to every temporary password

- **Expires after 7 days** (`TEMPORARY_PASSWORD_DAYS`). Sign-in with an expired
  one is refused: "Your temporary password has expired. Ask the school office
  to reset it."
- **Must be replaced at first sign-in.** Until the user chooses their own
  password, the backend answers every request except *view profile*,
  *change password*, *register this phone* and *sign out* with
  `403 password_change_required`. The app opens the *Choose your password*
  screen; this is enforced on the server, not only hidden in the app.
- **New password rules:** at least 8 characters, not all digits, not a common
  password, not similar to the user's name, not the same as the temporary one.
- **Changing a password signs out every other device.**
- **An admin reset** issues a new temporary password and signs the user out
  everywhere.
- **Deactivating an account** signs it out everywhere immediately and removes
  its phones from push notifications.

## What is needed to switch SMS on

### 1. Choose a provider

Any provider that can send transactional SMS in India works. Common choices:
MSG91, Fast2SMS, Twilio (India routes), Gupshup, Textlocal. Each quotes its own
price per SMS.

### 2. DLT registration (mandatory in India)

Indian carriers drop SMS that are not registered on a TRAI DLT portal
(Jio, Airtel, Vi, BSNL - registering on one is enough). This takes a few
working days and needs the school's documents.

1. **Register the school as a Principal Entity** - gives the *Entity ID*.
2. **Register a Header (sender id)**, 6 letters, e.g. `VIVSCH` - category
   *Transactional / Service Implicit*.
3. **Register this content template** exactly as the app sends it (the
   `{#var#}` parts are filled in per message):

   ```
   {#var#}: your app login is {#var#}. Temporary password: {#var#} . You will be asked to set your own password after signing in. Do not share this message.
   ```

   The approved template gets a *Template ID*. The wording lives in
   `backend/apps/accounts/services/sms/__init__.py`
   (`TEMPORARY_PASSWORD_TEMPLATE`); if DLT asks for a change, change both.

### 3. Add the provider adapter

One small class in `backend/apps/accounts/services/sms/` implementing
`send(phone_e164, message) -> SmsResult`, registered in `PROVIDERS`. Tell me
which provider you chose and I will add it with tests.

### 4. Configure `backend/.env` (never commit these)

```
SMS_PROVIDER=msg91            # the adapter name
SMS_API_KEY=                  # from the provider dashboard
SMS_SENDER_ID=VIVSCH          # the DLT header
SMS_DLT_ENTITY_ID=            # from DLT
SMS_DLT_TEMPLATE_ID=          # from DLT
TEMPORARY_PASSWORD_DAYS=7
```

Restart the backend, create a test account with your own mobile number, and
confirm the admin screen says *Sent by SMS* and the text arrives.
