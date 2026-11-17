# mobile_app — TANFINET POP PM Field App (Flutter)

Flutter app for field engineers, Android-first. Clean modular architecture:
each feature is isolated under `lib/features/<feature>/` in
`data` / `domain` / `presentation` layers.

## Structure

```
lib/
├── main.dart                 # entry point
├── app/                      # app widget, theming, routing
├── core/                     # cross-cutting concerns
│   ├── constants/
│   ├── errors/
│   ├── network/              # API client setup (later step)
│   ├── theme/
│   └── utils/
├── features/
│   ├── auth/                 # employee login
│   ├── location_selection/   # District → Block → GP → POP
│   ├── pm_visit/             # 5 mandatory photos, GPS, geofence, watermark
│   ├── sync/                 # offline storage + Drive/backend sync
│   └── dashboard/            # POP visit history (device-local views)
└── shared/
    ├── widgets/               # reusable UI components
    └── models/                # shared data models
```

Each `data` / `domain` / `presentation` subfolder currently contains only a
`.gitkeep` placeholder — no logic has been implemented yet.

## Status

This is a scaffold: `main.dart` renders a placeholder screen so the project
structure can be verified. No camera, GPS, geofencing, offline sync, or
Google Drive upload logic exists yet.

## Running (next step)

The Flutter SDK is **not installed in this cloud container**, so the app
has not been built or run here. To verify it on a machine with Flutter
installed:

```bash
cd mobile_app
flutter pub get
flutter analyze
flutter test
flutter run   # requires a connected device/emulator
```

Note: this skeleton was hand-written (no `flutter create` available in this
environment), so platform runner folders (`android/`, `ios/`) do not exist
yet. Running `flutter create .` inside `mobile_app/` on a machine with the
Flutter SDK will generate them without touching the existing `lib/` or
`pubspec.yaml` — recommended as the first action in the next step, before
any camera/GPS code is added.
