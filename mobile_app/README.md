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
│   ├── auth/                 # employee login (implemented)
│   │   ├── data/              # AuthApiClient, DevLoginAuthRepository
│   │   ├── domain/            # AuthRepository interface, EmployeeProfile, AuthFailure
│   │   └── presentation/      # AuthController, LoginScreen, ProfileScreen
│   ├── location_selection/   # District → Block → GP → POP
│   ├── pm_visit/             # 5 mandatory photos, GPS, geofence, watermark
│   ├── sync/                 # offline storage + Drive/backend sync
│   └── dashboard/            # POP visit history (device-local views)
└── shared/
    ├── widgets/               # reusable UI components
    └── models/                # shared data models
```

Every other feature's `data` / `domain` / `presentation` subfolder still
contains only a `.gitkeep` placeholder — not implemented yet.

## Status

**Employee Login is implemented.** The app opens on `LoginScreen`
(Employee ID + mobile number), and on success shows `ProfileScreen`
(Employee ID, name, assigned district).

Authentication currently calls the backend's development/test login
endpoint (`POST /api/v1/auth/login`), which matches a pre-registered
employee by Employee ID + mobile number — no OTP, no password. This is
intentionally swappable: `LoginScreen`/`AuthController` depend only on the
`AuthRepository` interface (`lib/features/auth/domain/repositories/`), so
a future OTP-based repository replaces `DevLoginAuthRepository`
(`lib/features/auth/data/`) without touching the UI.

The backend auto-seeds two demo accounts in dev mode (see
`backend/app/db/seed_dev_data.py`) so the screen can be tested immediately:

| Employee ID | Mobile Number | District |
|---|---|---|
| `ENG001` | `9876543210` | Chennai |
| `ENG002` | `9123456780` | Madurai |

By default the app points at `http://10.0.2.2:8000` (the Android
emulator's alias for the host machine running the FastAPI backend on
`localhost:8000`). Override with:
`flutter run --dart-define=API_BASE_URL=http://<host>:8000`.

No camera, GPS, geofencing, offline sync, or Google Drive upload logic
exists yet.

## Running (next step)

The Flutter SDK is **not installed in this cloud container**, so the app
has not been built or run here. To verify it on a machine with Flutter
installed:

```bash
cd mobile_app
flutter pub get
flutter analyze
flutter test
flutter run   # requires a connected device/emulator; backend must be running
```

These commands (`pub get`, `analyze`, `test`) have **not been run** in
this development session — see the top-level report for why.

Note: this skeleton was hand-written (no `flutter create` available in this
environment), so platform runner folders (`android/`, `ios/`) do not exist
yet. Running `flutter create .` inside `mobile_app/` on a machine with the
Flutter SDK will generate them without touching the existing `lib/` or
`pubspec.yaml` — recommended as the first action in the next step, before
any camera/GPS code is added.
