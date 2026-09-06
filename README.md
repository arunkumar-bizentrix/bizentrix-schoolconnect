# Bizentrix SchoolConnect

Structured, role-based school communication and homework management platform (replacing scattered WhatsApp groups with an Android-first mobile app).

---

## 📱 Tech Stack
- **Frontend**: Flutter (Android-first), Riverpod, GoRouter, Dio, Google Fonts
- **Backend**: Python, Django, Django REST Framework (DRF)
- **Database**: PostgreSQL
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **File Storage**: S3-compatible storage (for homework sheets, circular PDFs, image attachments)
- **Version Control**: Git

---

## 🏗️ Project Architecture

```
d:\school\
├── mobile/                           # Flutter Mobile Application
│   ├── pubspec.yaml                  # App dependencies & assets
│   ├── analysis_options.yaml         # Linting configuration
│   ├── assets/
│   │   ├── icons/                    # App icons & SVGs
│   │   └── images/                   # App logos & illustrations
│   └── lib/
│       ├── main.dart                 # Application entry point & ProviderScope
│       ├── app.dart                  # MaterialApp.router configuration & theme
│       ├── core/                     # Shared core utilities & infrastructure
│       │   ├── constants/            # App constants, roles, and color tokens
│       │   ├── errors/               # Failure & exception definitions
│       │   ├── network/              # Dio client, auth interceptor & API endpoints
│       │   ├── routing/              # GoRouter configuration & role navigation guards
│       │   ├── storage/              # Secure token & session storage
│       │   └── theme/                # Typography, light theme & UI components
│       └── features/                 # Modular feature-first architecture
│           ├── auth/                 # Role-based login & user models
│           ├── dashboard/            # Admin, Teacher, and Parent dashboards
│           ├── homework/             # Homework list & attachment previews
│           └── announcements/        # School circulars & broadcast notices
│
├── backend/                          # Django REST Framework Backend (Phase 2)
└── README.md
```

---

## 🚀 Getting Started with the Mobile App

### Prerequisites
1. **Flutter SDK**: Ensure Flutter 3.19+ is installed and added to your system's `PATH`.
2. **Android Studio / Android SDK**: For running the Android emulator or deploying to a physical device.

### Running the App
```bash
cd mobile
flutter pub get
flutter run
```

---

## 👥 Role Capabilities (MVP)

1. **Admin**:
   - Manage school details, teachers, students, and classes.
   - Broadcast urgent and general announcements with PDF circulars.
   - Overview metrics of classes and homework assignments.

2. **Teacher**:
   - Assign homework to specific classes with due dates and attachments (PDF/images).
   - View student submissions.
   - Receive school administration circulars.

3. **Parent**:
   - Switch between enrolled children (multi-student support).
   - View daily homework with subject badges, due dates, and downloadable attachments.
   - View official school announcements and urgent notices.
