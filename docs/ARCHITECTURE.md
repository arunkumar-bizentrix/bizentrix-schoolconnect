# Bizentrix SchoolConnect — Architecture

A structured school-communication and homework platform for **one school**:
Vivekananda School, Bagalur. A Django REST backend serves an Android-first
Flutter app used by three roles — Admin, Teacher and Parent.

This document is the map. Read it before adding a feature, and update it when
you change the shape of something described here.

---

## 1. Project structure

```
d:\school\
├── backend/          Django + DRF + PostgreSQL API
├── mobile/           Flutter application (the product client)
└── docs/
    └── ARCHITECTURE.md
```

There is exactly one client: the Flutter app. If you need a web view of
something, add it to the app or to the Django admin — do not start a second
parallel client.

---

## 2. Backend structure

```
backend/
├── manage.py                 Uses config.settings_test automatically for `test`
├── requirements.txt
├── .env                      Real secrets. Gitignored. Never committed.
├── .env.example              Every key the app reads, with safe placeholders
│
├── config/
│   ├── settings.py           Production/development settings
│   ├── settings_test.py      Test overrides: fast hasher, no external I/O
│   ├── urls.py               Root URL map; all APIs under /api/v1/
│   ├── asgi.py
│   └── wsgi.py
│
└── apps/
    ├── schools/              The School record + school context resolution
    │   ├── models.py
    │   ├── services.py       ← get_school_for() / attach_user_to_school()
    │   └── admin.py
    ├── accounts/             User, roles, JWT + OTP authentication
    │   ├── models.py         User(AbstractUser), OTPVerification
    │   ├── backends.py       Sign in with username, phone number or email
    │   ├── serializers.py
    │   ├── views.py          Login, register, profile, OTP, people management
    │   ├── urls.py
    │   └── services/         accounts.py (admin-created logins),
    │                         email_service.py, whatsapp_service.py
    ├── students/             Class, Student, StudentClassEnrollment
    │   ├── models.py  serializers.py  views.py  permissions.py  urls.py
    │   └── today.py          The parent's Today screen in one request
    ├── homework/             Homework
    │   ├── models.py  serializers.py  views.py  permissions.py  urls.py
    ├── announcements/        Announcement (+ attachment validators.py)
    ├── attendance/           Attendance (one row per student per day)
    ├── timetable/            Subject, TimetableSlot
    ├── exams/                Exam, ExamPaper, Mark
    │   └── services.py       Totals, ranks, publishing, report cards
    └── notifications/        Notification + NotificationService fan-out, push
```

### One responsibility per file

| File | Owns |
|---|---|
| `models.py` | Database structure, model-level integrity (`clean()` for the Django admin) |
| `serializers.py` | API input validation and output representation. **This is where API-layer rules are enforced** — DRF does not call `Model.clean()` |
| `views.py` | HTTP orchestration: queryset scoping, role gating on write, response shape |
| `permissions.py` | Authorization only. Must never write to the database |
| `services/`, `services.py` | Business logic used by more than one view, or logic with external I/O |
| `validators.py` | Reusable field validation |
| `admin.py` | Django admin registration |

---

## 3. Flutter structure

```
mobile/lib/
├── main.dart                 Entry point, ProviderScope
├── app.dart                  MaterialApp.router, theme
│
├── core/                     Cross-cutting infrastructure
│   ├── constants/            app_colors.dart, app_constants.dart
│   ├── errors/               failures.dart
│   ├── network/              api_client.dart (Dio + auth/refresh), api_endpoints.dart
│   ├── routing/              app_router.dart (GoRouter + auth redirect)
│   ├── storage/              token_storage.dart (secure JWT/session storage)
│   ├── theme/                app_theme.dart
│   └── utils/                role_access.dart  ← what each role may do
│
├── features/                 One folder per domain; each holds what it owns
│   ├── auth/           models/ providers/ screens/
│   ├── dashboard/      screens/          (admin, teacher, parent, nav shell)
│   ├── classes/        models/ providers/ screens/
│   ├── students/       models/ providers/ screens/   (+ child_scope.dart)
│   ├── homework/       models/ providers/ screens/
│   ├── announcements/  models/ providers/ screens/
│   ├── notifications/  models/ providers/ screens/
│   └── profile/        screens/
│
└── shared/widgets/           Widgets used by more than one feature
    ├── info_row.dart         Labelled detail line
    ├── list_state_views.dart EmptyState, ErrorStateView, LoadingView
    └── user_avatar.dart      Picture, or initials — never a stock photo
```

### The only permitted data flow

```
Screen (UI composition, role-gated display)
   ↓ ref.watch / ref.read
Provider (StateNotifier — request state, list state, error text)
   ↓
ApiClient (Dio: base URL, auth header, token refresh, error → Failure)
   ↓
Django REST API
```

A screen must never construct a Dio call, build a URL, or hold domain rules.
If a screen needs a rule (for example "which homework belongs to the selected
child"), that rule belongs beside the feature's providers — see
`features/students/providers/child_scope.dart`.

There is deliberately **no repository layer**. The providers are thin and call
`ApiClient` directly; adding repositories would be indirection without a second
data source to justify it.

---

## 4. Authentication flow

Three ways in, one session model.

**Password** — `POST /api/v1/auth/token/` → `{access, refresh}`, then
`GET /api/v1/auth/me/` for the profile and role. The identifier may be the
username, the 10-digit mobile number or the email
(`accounts/backends.py`); nobody at a school remembers a generated username.

**Who gets an account** — parents may sign up themselves (they see nothing
until the admin links a child). Teacher accounts are created only by the
admin (`POST /api/v1/auth/staff/`), which returns a one-time password to hand
over; `auth/register/` refuses `role=TEACHER`. Anyone can install the app, so
a self-made teacher account would be one class assignment away from
children's records.
(`POST /api/v1/auth/login/` does both in one call and is used by the backend
test suite; the app uses the two-step form.)

**Email OTP** — `POST /api/v1/auth/otp/email/send/` then
`POST /api/v1/auth/otp/email/verify/` → tokens + profile.

**WhatsApp OTP** — `POST /api/v1/auth/otp/send/` then `.../otp/verify/`.

OTP rules (enforced in `accounts/serializers.py` and `OTPVerification`):
6 digits from `secrets`, stored only as a salted SHA-256 hash, 5-minute expiry,
max 5 attempts, single use, 60-second resend cooldown and 10/hour per
destination. The OTP is never returned in a response, printed, or logged —
including in development.

**Session lifecycle in the app**
- `TokenStorage` keeps access + refresh tokens and the cached profile in
  `flutter_secure_storage`.
- `ApiClient` attaches `Authorization: Bearer <access>` to every request.
- On `401`, the interceptor refreshes once with the refresh token and replays
  the request; if the refresh fails it clears the session.
- `AuthNotifier.restoreSession()` shows the cached profile immediately at
  launch, then re-validates against `/auth/me/`.
- `app_router.dart` redirects to `/login` whenever there is no session.

**Throttling** — the credential endpoints declare `ScopedRateThrottle`
explicitly (`auth` scope on token/refresh/login/register, `otp` scope on the
four OTP endpoints). Rates come from `THROTTLE_RATE_AUTH` / `THROTTLE_RATE_OTP`.
Ordinary data endpoints are deliberately not throttled.

---

## 5. Role system

The backend is the authority. The app hides what a role cannot do, but every
request is re-checked server-side. `core/utils/role_access.dart` mirrors the
table below — keep the two in sync.

| Capability | Admin | Teacher | Parent |
|---|:--:|:--:|:--:|
| View classes | all | assigned only | children's only |
| Create / edit / delete classes | ✅ | ❌ | ❌ |
| Assign teachers to a class | ✅ | ❌ | ❌ |
| View students | all | in assigned classes | own children only |
| Create / edit / delete students | ✅ | ❌ | ❌ |
| Manage class enrollments | ✅ | ❌ | ❌ |
| Link / unlink parents | ✅ | ❌ | ❌ |
| Create teacher / parent accounts, reset passwords, deactivate | ✅ | ❌ | ❌ |
| Set a class's class teacher | ✅ | ❌ | ❌ |
| Mark attendance | ✅ | class teacher (any assigned teacher if none set) | ❌ (own children, read only) |
| Create exams, publish results | ✅ | ❌ | ❌ |
| Enter marks | ✅ | subject they teach in that class (from the timetable), or as class teacher | ❌ |
| Class result sheet with ranks | ✅ | classes they teach | ❌ |
| Report card | all | students they teach | own children, published exams only |
| Homework CRUD | all classes | assigned classes only | ❌ (read only) |
| Class announcements | ✅ | assigned classes only | ❌ (read only) |
| School-wide announcements | ✅ | ❌ | ❌ (read only) |
| Notifications | own | own | own |
| Profile | own | own | own |

Teachers read classes and students; they do not administer them. Their write
access is homework, class announcements, attendance (as class teacher) and
marks (for the subjects they teach), always scoped to their own classes.

Enforced by `students/permissions.py` (`IsSchoolMember`),
`homework/permissions.py` (`IsHomeworkAuthorized`) and
`announcements/permissions.py` (`IsAnnouncementAuthorized`), plus role checks
in each viewset's `perform_create` / `perform_destroy`.

---

## 6. Single-school context

This is not a multi-tenant SaaS. There is no school switcher, no school
selector at login, and the client never sends a school id for authorization.

Every domain model still carries a `school` foreign key. That is deliberate:
it keeps referential integrity, makes historical queries safe, and costs
nothing. What was removed is the *scattered resolution logic*.

**One place resolves the school** — `apps/schools/services.py`:

```python
get_default_school()          # the School row this deployment serves
get_school_for(user)          # user's school, else the default — read-only
get_school_id_for(user)       # same, without fetching the row
attach_user_to_school(user)   # persists the association (auth / first write only)
```

Nothing else may call `School.objects.first()`. Permission classes use
`get_school_for()` and never write.

---

## 7. Data relationships

```
School
 ├── Subject
 ├── Exam ──── ExamPaper (exam × class × subject, max/pass marks)
 │                └── Mark (paper × student)
 └── Class ──── teachers (M2M → User, role=TEACHER)
      │   └── class_teacher (FK → one of the teachers)
      ├── Student ──── parents (M2M → User, role=PARENT)
      │    ├── StudentClassEnrollment   (per academic year history)
      │    └── Attendance               (one per day)
      ├── TimetableSlot (weekday × period → subject, teacher)
      ├── Homework      (classroom, optionally one student)
      └── Announcement  (audience_type=CLASS → target_class)
```

**Teacher → Class → Students → Parents**
`Class.teachers` is the single source of "which classes a teacher owns".
Teachers see students via `class_enrolled__teachers=user`.

**Parent → Children → Class**
`Student.parents` is the single source of "whose child this is".
`GET /api/v1/parent/children/` returns exactly the requesting parent's children.

**Academic year**
Canonical format `YYYY-YYYY`, normalized by `normalize_academic_year()`.
`Class.academic_year` is authoritative; `StudentClassEnrollment` preserves the
per-year history so a promotion does not erase last year's record.

---

## 8. Homework flow

1. Teacher (or admin) posts to `POST /api/v1/homework/` with a `classroom`,
   `subject`, `title`, `due_date` and optional `attachment` / `student`.
2. `IsHomeworkAuthorized` confirms the role; `perform_create` confirms the
   teacher is assigned to that class.
3. `HomeworkSerializer` validates the dates and that any named student is
   actually enrolled in the class.
4. `NotificationService.create_homework_notifications()` fans out one
   notification per unique parent — a parent with two children in the class
   gets one, not two.
5. Parents read it through `GET /api/v1/homework/`, which is scoped to their
   children's classes plus anything addressed to a child individually.

## 9. Announcement flow

1. Admin posts school-wide or class announcements; a teacher may post only to
   a class assigned to them, and never school-wide.
2. `AnnouncementSerializer` enforces the audience rules (`CLASS` requires a
   `target_class`; `SCHOOL` must not have one) and validates the attachment
   (PDF/JPG/PNG/WebP, 10 MB).
3. `NotificationService.create_announcement_notifications()` fans out to the
   target class's parents, or to every active parent for a school-wide notice.
4. Parents see school circulars plus class notices for their children's classes.

## 10. Notification flow

```
Homework / Attendance / Announcement created
        ↓ NotificationService (deduplicated per parent)
Notification rows (one per recipient)
        ├─→ GET /api/v1/notifications/     → app list + unread badge
        └─→ push.send_to_tokens(...)       → the phone's notification tray
```

Endpoints: list, `POST .../{id}/read/`, `POST .../mark-all-read/`,
`GET .../unread-count/`. Every one is scoped to `recipient=request.user`.

**Push delivery** lives in `notifications/push.py` (Firebase Cloud Messaging
v1). `NotificationService._push()` calls it after each fan-out, so no caller
has to know push exists. Two properties matter:

- It **never raises**. A dead network or a rejected token must not fail the
  request that set the homework.
- It is **optional**. Without a service-account file `is_configured()` is
  `False`, every send is a logged no-op, and the product still works in-app.

Devices register at `POST /api/v1/notifications/register-device/` (upsert on
the token) and release on sign-out via `DELETE` — a user may only delete their
own token. Tokens Firebase reports as dead are deleted during the next
fan-out. Setup steps are in [PUSH_SETUP.md](PUSH_SETUP.md).

**Exams and results**

1. The admin creates an exam, picking classes and subjects; one `ExamPaper` is
   created per class and subject with common maximum and pass marks, which
   can then be adjusted per paper.
2. Teachers enter marks per paper. Who teaches a subject comes from the
   timetable, so it is recorded once; the class teacher may enter any subject
   of their class. A school without a timetable is not locked out - with no
   period of that subject scheduled, any assigned teacher may enter it.
3. Totals, percentages, pass/fail and ranks are computed from `Mark` rows on
   every read (`exams/services.py`), never stored, so a corrected mark can
   never leave a stale rank behind. Ranking is standard competition ranking
   (two on 450 are both 2nd; the next is 4th) and only students with every
   paper entered are ranked.
4. Results are private to staff until the admin publishes. Publishing refuses
   while marks are missing unless the admin explicitly accepts that, locks
   marks, and sends each parent their own child's result. Unpublishing
   reopens marks for correction.
5. A report card is built from the student's own marks, so last year's
   results survive promotion into a new class.

**Parent Today** — `GET /api/v1/parent/today/` returns, per child: today's
attendance and the year's percentage, today's periods, homework given today
and due in the next three days, and the latest published result. One request
instead of four screens.

**Dates** — `TIME_ZONE = 'Asia/Kolkata'`. "Today" for attendance, homework
and the Today screen rolls over at Indian midnight. Stored datetimes stay UTC.

---

## 11. API structure

Everything lives under `/api/v1/`.

| Route | Methods | Notes |
|---|---|---|
| `auth/token/`, `auth/token/refresh/` | POST | JWT, throttled |
| `auth/login/` | POST | Tokens + profile in one call |
| `auth/register/` | POST | Parent self-registration (teacher refused) |
| `auth/me/` | GET, PATCH | Profile, including `profile_picture` upload |
| `auth/staff/?role=TEACHER\|PARENT` | GET, POST | Admin only. GET lists (`?search=`, `?include_inactive=1`, `?page=` for a paginated envelope); POST creates an account and returns a one-time password |
| `auth/staff/{id}/` | PATCH | Admin: edit name/phone/email, `is_active` to deactivate |
| `auth/staff/{id}/reset-password/` | POST | Admin: new one-time password |
| `auth/otp/email/send/`, `auth/otp/email/verify/` | POST | Email OTP |
| `auth/otp/send/`, `auth/otp/verify/` | POST | WhatsApp OTP |
| `classes/`, `classes/{id}/` | GET, POST, PATCH, DELETE | Writes: admin only |
| `students/`, `students/{id}/` | GET, POST, PATCH, DELETE | Writes: admin only |
| `students/{id}/enrollments/` | GET, POST | POST: admin only |
| `students/{id}/link-parent/`, `unlink-parent/` | POST | Admin only |
| `parent/children/` | GET | The caller's own children |
| `parent/today/` | GET | Parent's Today view for each child (`?student_id=` for one) |
| `attendance/mark/`, `sheet/`, `summary/` | POST, GET | Marking: admin + class teacher |
| `subjects/`, `timetable/`, `timetable/week/`, `timetable/my/` | GET, POST, PATCH, DELETE | Writes: admin only |
| `exams/`, `exams/{id}/` | GET, POST, PATCH, DELETE | Writes: admin; delete only before marks exist |
| `exams/{id}/papers/`, `add-papers/`, `results/`, `progress/`, `publish/`, `unpublish/` | GET, POST | Results: staff; publish: admin |
| `exam-papers/{id}/`, `exam-papers/{id}/marks/` | PATCH, DELETE, GET, POST | Marks: subject teacher, class teacher, admin |
| `report-card/?student_id=` | GET | Parents: own children, published only |
| `homework/`, `homework/{id}/` | GET, POST, PATCH, DELETE | Writes: admin + assigned teacher |
| `announcements/`, `announcements/{id}/` | GET, POST, PATCH, DELETE | School-wide: admin only |
| `notifications/…` | GET, POST | Always scoped to the caller |

**Conventions**
- List endpoints paginate (`PAGE_SIZE = 20`) and return `{count, next, previous, results}`.
  `parent/children/` is the one exception and returns a bare list.
- Filters are query parameters: `academic_year`, `class_id`, `section`,
  `subject`, `priority`, `audience_type`, `from_date`, `to_date`, `is_active`.
- Errors are DRF-standard: `400` with field errors, `401`, `403`, `404`, `429`.
- The client keeps every path in `core/network/api_endpoints.dart`. Nothing
  builds a URL by hand.

---

## 12. Environment configuration

All backend configuration comes from environment variables, with `.env` as the
local fallback. `.env` is gitignored and has never been committed; `.env.example`
documents every key.

Real environment variables **take precedence** over `.env`
(`load_dotenv(..., override=False)`), so containers and CI can configure the app
without editing files.

Keys: `DEBUG`, `SECRET_KEY`, `ALLOWED_HOSTS`, `DB_*`, `CORS_ALLOWED_ORIGINS`,
`EMAIL_*`, `WHATSAPP_*`, `THROTTLE_RATE_AUTH`, `THROTTLE_RATE_OTP`.

The Flutter API base URL is a compile-time define, not a stored setting:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.0.6:8000/api/v1
```

**Never** commit a secret. If one is exposed, rotate it — removing the line is
not enough.

---

## 13. Where to add future features

| You want to… | Do this |
|---|---|
| Add an API endpoint | New viewset/action in the owning app; register in that app's `urls.py`; it is already mounted under `/api/v1/` |
| Add a permission rule | Extend the app's `permissions.py`, then mirror it in `core/utils/role_access.dart` and in §5 of this document |
| Add a screen | `features/<domain>/screens/`; get data from a provider, never from Dio |
| Add app state | `features/<domain>/providers/`; keep `core/` free of feature state |
| Add a reusable widget | `shared/widgets/` once a second feature needs it — not before |
| Add business logic | Backend `services.py` if it is a server rule; `features/<domain>/providers/` if it is a client rule |
| Add a new role | `User.Role`, then every `permissions.py`, then `RoleAccess`, then §5 |

---

## 14. Coding conventions

**Python**
- `snake_case` for functions and variables, `PascalCase` for classes,
  `UPPER_SNAKE` for constants.
- Imports at module top. A function-level import means a real circular
  dependency — fix the dependency instead.
- Do not call `School.objects.first()`; use `apps.schools.services`.
- Permission classes are read-only.

**Dart**
- `lower_snake_case.dart` filenames, `PascalCase` classes, `camelCase` members.
- One name per concept. The id of a Class is `classId` everywhere in Dart, even
  where the JSON key is `classroom`, `class_enrolled` or `target_class`.
  `targetClassId` is kept only where "the target of an announcement" is a
  genuinely different idea.
- Provider write methods return `Future<String?>`: `null` means success,
  anything else is the message to show the user. Never swallow a server error.
- Colours come from `AppColors`. Add a token rather than inlining a new hex.
- Placeholders never impersonate real content — no stock photos of people.

**Tests**
- Backend: `python manage.py test` (auto-selects `config.settings_test`).
- Flutter unit tests live in `mobile/test/` and must be hermetic — no network.
- Tests that need a running, seeded backend live in `mobile/test_live/` and are
  run deliberately: `flutter test test_live`.
