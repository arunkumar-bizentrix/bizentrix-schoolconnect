# Bizentrix SchoolConnect

Structured, role-based school communication and homework management for
**Vivekananda School, Bagalur** — replacing scattered WhatsApp groups with an
Android-first mobile app.

> **Architecture, conventions and where to add things:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Tech Stack

- **Mobile**: Flutter (Android-first), Riverpod, GoRouter, Dio, Google Fonts
- **Backend**: Python, Django 5.1, Django REST Framework, SimpleJWT
- **Database**: PostgreSQL
- **Authentication**: JWT, with password, email OTP and WhatsApp OTP sign-in
- **Notifications**: in-app (stored and polled). Push is not implemented yet.
- **File storage**: local `MEDIA_ROOT` (homework attachments, circular PDFs,
  profile pictures). Object storage is not wired up yet.

---

## Layout

```
d:\school\
├── backend/     Django REST API      (see docs/ARCHITECTURE.md §2)
├── mobile/      Flutter app          (see docs/ARCHITECTURE.md §3)
└── docs/        Architecture notes
```

---

## Running the backend

```bash
cd backend
python -m venv venv
venv/Scripts/activate          # Windows;  source venv/bin/activate on Unix
pip install -r requirements.txt
cp .env.example .env           # then fill in DB and email credentials
python manage.py migrate
python manage.py seed_demo_users
python manage.py runserver 0.0.0.0:8000
```

## Running the app

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://192.168.0.6:8000/api/v1
```

Replace the IP with your machine's LAN address (use `http://10.0.2.2:8000/api/v1`
for the Android emulator). Without the define it falls back to the value in
`lib/core/constants/app_constants.dart`.

---

## Tests

```bash
cd backend && python manage.py test
```

```bash
cd mobile && flutter analyze && flutter test
```

`flutter test` is hermetic — no backend required. The API contract tests that
*do* need a running, seeded backend are kept separate and run on demand:

```bash
cd mobile && flutter test test_live
```

---

## Roles

**Admin** — full management of classes, students, teachers, parents, homework,
announcements and school settings.

**Teacher** — reads their assigned classes and the students in them; creates and
manages homework and class announcements for those classes. Teachers do not
administer class or student records.

**Parent** — switches between their children; reads that child's homework, class
notices and school circulars; receives notifications.

The full capability matrix is in [docs/ARCHITECTURE.md §5](docs/ARCHITECTURE.md).
The backend enforces it; the app only hides what a role cannot do.
