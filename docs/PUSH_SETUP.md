# Push notifications (Firebase Cloud Messaging)

The app and the backend are fully wired for push. Nothing here is code work -
what remains is one account setup that must be done from **your** Google
account, because it creates a project that belongs to the school.

Until the two files below exist, everything keeps working: notifications appear
inside the app, and `push_enabled` simply reports `false`.

## What you need to do (about 10 minutes)

### 1. Create the Firebase project

1. Open <https://console.firebase.google.com> and sign in.
2. **Add project** -> name it `Bizentrix SchoolConnect` -> Continue.
3. Google Analytics is not needed. Turn it off -> **Create project**.

### 2. Android app -> `google-services.json`

1. In the project, click the **Android** icon ("Add app").
2. Android package name - this must match exactly:

   ```
   com.bizentrix.schoolconnect
   ```

3. App nickname: `SchoolConnect`. Leave the SHA-1 field empty.
4. **Register app** -> **Download google-services.json**.
5. Put that file at:

   ```
   mobile/android/app/google-services.json
   ```

6. Skip the rest of the wizard ("Next" until "Continue to console") - the
   Gradle changes it describes are already in the project.

### 3. Server key -> `firebase-service-account.json`

1. Gear icon (top left) -> **Project settings** -> **Service accounts** tab.
2. **Generate new private key** -> **Generate key**. A `.json` file downloads.
3. Rename it and put it at:

   ```
   backend/firebase-service-account.json
   ```

4. In `backend/.env`, set:

   ```
   FIREBASE_SERVICE_ACCOUNT_FILE=firebase-service-account.json
   ```

5. Restart the Django server.

> This file is a password to the school's Firebase project. It is already in
> `.gitignore`; do not commit it, email it, or paste it into a chat.

### 4. Check it

Sign in on a real Android phone (push does not work in the web preview or on an
emulator without Play Services). The app asks for notification permission the
first time - allow it.

Then, from the backend:

```bash
python manage.py shell -c "from apps.notifications import push; print(push.is_configured())"
```

`True` means the server can deliver. Now set a homework from a teacher account
and the parent's phone should buzz.

## How it works

- On sign-in the app asks Firebase for a device token and POSTs it to
  `/api/v1/notifications/register-device/`. One row per device per user.
- Whenever the backend creates notifications - homework, attendance,
  announcements - it also sends them to that user's device tokens.
- On sign-out the app deletes its own token first, so the next person to use
  that phone does not receive the previous account's notifications.
- Tokens Firebase reports as dead are deleted automatically, so a wiped phone
  does not leave a row behind forever.

## Rotating the service-account key

Do this whenever a key may have been exposed (pasted into a chat, emailed,
left on a shared machine). The key that was set up on 14 Sep 2026 must be
treated as exposed.

1. **Create the new key** - Firebase console > Project settings > Service
   accounts > *Generate new private key*.
2. **Store it outside the repository**, for example
   `C:/secure/schoolconnect/firebase-service-account.json`, readable only by
   the account that runs the backend.
3. **Point the backend at it** in `backend/.env`:

   ```
   FIREBASE_SERVICE_ACCOUNT_FILE=C:/secure/schoolconnect/firebase-service-account.json
   ```

4. **Restart the backend**, then verify - it prints the project id and pass or
   fail, never the key:

   ```bash
   python manage.py check_push
   ```

5. **Revoke the old key - this is the step that actually makes it useless.**
   Google Cloud console > IAM & Admin > Service accounts >
   `firebase-adminsdk-…@bizentrix-schoolconnect` > *Keys*. Delete every key
   except the one created in step 1 (compare the creation dates).
6. **Delete the old file** from the backend folder
   (`backend/firebase-service-account.json`).
7. Run `python manage.py check_push` again. It must still pass.

Phones do not need to do anything: device tokens belong to the Firebase
project, not to the key.

What the backend guarantees:

- The key is read from the file named in the environment and is never logged,
  printed, returned by an API, or stored in the database.
- `.gitignore` refuses `*service-account*.json`, `*firebase-adminsdk*.json`,
  `google-services.json` and `.env` anywhere in the repository.
- If Firebase rejects the credential (for example after the old key is
  revoked but before the new one is installed), sending stops at once, the
  cached token is dropped, and **no parent's device is retired** - only tokens
  Firebase reports as dead (`UNREGISTERED`) are deactivated.
- Signing out deletes the phone's registration; a deactivated account's
  devices are deleted as well.

## If push stays silent

| Symptom | Cause |
| --- | --- |
| `push_enabled: false` in the register response | the backend has no service-account file, or the path in `.env` is wrong |
| App logs `Push unavailable` at launch | `google-services.json` is missing or in the wrong folder |
| Nothing arrives on one phone only | notification permission was denied - Settings -> Apps -> SchoolConnect -> Notifications |
| Works in foreground, not when closed | battery optimisation is killing the app - exclude it in Settings -> Battery |

## Known local issue

`flutter pub get` warns:

> Building with plugins requires symlink support. Please enable Developer Mode
> in your system settings.

Turn on **Settings -> System -> For developers -> Developer Mode** in Windows.
Without it the Android build cannot link the Firebase plugins. This is a
Windows setting, so it has to be switched on by you.
