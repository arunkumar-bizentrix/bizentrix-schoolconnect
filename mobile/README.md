# SchoolConnect — Flutter app

The mobile client for Bizentrix SchoolConnect. Android-first.

See [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for the layer rules,
folder conventions and role model. The short version:

```
Screen  →  Provider (Riverpod StateNotifier)  →  ApiClient (Dio)  →  Django API
```

A screen never calls Dio, builds a URL, or holds a domain rule.

## Run

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://192.168.0.6:8000/api/v1
```

Use `http://10.0.2.2:8000/api/v1` for the Android emulator.

## Checks

```bash
flutter analyze
flutter test          # hermetic: no backend needed
flutter test test_live   # needs a running, seeded backend on :8000
```

## Layout

```
lib/
├── core/       constants, errors, network, routing, storage, theme, utils
├── features/   auth, dashboard, classes, students, homework,
│               announcements, notifications, profile
│               — each with models/, providers/, screens/
└── shared/widgets/   widgets used by more than one feature
```
