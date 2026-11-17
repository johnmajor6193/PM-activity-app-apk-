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
│   ├── location_selection/   # District → Block → GP → POP (implemented)
│   │   ├── data/              # LocationApiClient, LocationRepositoryImpl
│   │   ├── domain/            # LocationRepository interface, District/Block/Gp/PopSummary/PopDetail
│   │   └── presentation/      # PopSelectionController, PopSelectionScreen
│   ├── pm_visit/             # 5 mandatory photos, per-photo GPS (implemented; no watermark/geofence/Drive yet)
│   │   ├── data/              # CameraCaptureService, LocationService, local_database.dart (sqflite), SqflitePmVisitRepository
│   │   ├── domain/            # PmVisitRepository interface, PmVisit/PmPhotoRecord/GpsReading/PhotoCategory
│   │   └── presentation/      # PmVisitController, PmVisitScreen
│   ├── sync/                 # Drive upload / backend submission (later step — local storage already exists, see pm_visit)
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

**POP Selection is implemented.** From `ProfileScreen`, "Select POP"
opens `PopSelectionScreen`: cascading District → Block → GP → POP
dropdowns, each loaded from the backend as the one above it is chosen,
ending in a details card (POP ID, name, District, Block, GP, Active/
Inactive status).

**No map, coordinates, or geofence status is shown.** The official POP
latitude/longitude master data has not been supplied yet, so this
screen does not request, display, or fake any GPS/geofence information
for a POP — see `PopDetail`
(`lib/features/location_selection/domain/entities/pop_detail.dart`).
This is separate from per-photo GPS capture, implemented below.

**PM Photo Capture is implemented.** From the POP details card,
"Start PM Visit" opens `PmVisitScreen`: a checklist of the 5 mandatory
photo categories (POP Rack, UPS & Battery, Busbar, Earth Pit Chamber,
Earth Pit Open with Rod), each starting Pending.

- **Capture Photo** opens the device's native camera
  (`image_picker` with `ImageSource.camera`) — there is no gallery
  option anywhere in this flow, and none is planned; this is the
  intended production capture method, not a placeholder.
- A fresh, live GPS fix (`geolocator`) is captured **at the moment of
  that specific photo** — not once per visit, not reused between
  categories.
- The photo + its GPS reading are shown on a review sheet (preview
  image, capture time, latitude, longitude, accuracy) with **Retake**
  (discards, category stays Pending) and **Confirm** (saves, category
  becomes Completed).
- **No geofence check happens anywhere in this flow.** The captured
  GPS is stored as-is; it is never compared against a POP coordinate,
  because POP coordinates don't exist yet (see POP Selection above).
- "Submit PM Visit" stays disabled until all 5 categories are
  Completed. Tapping it once enabled only shows a placeholder message —
  the actual submission workflow is a later module.

Everything is stored **only on the device** (SQLite via `sqflite`), so
a visit and its confirmed photos survive app restarts and need no
network connection — see `lib/features/pm_visit/data/local_database.dart`
and `docs/data-model.md` ("PM Visit & PM Photo — Local (On-Device)
Implementation"). There is no cloud sync, Drive upload, or GPS
watermark yet; the schema has nullable columns reserved for them.

No geofencing, GPS watermark, offline *sync* (as opposed to offline
*storage*, which is implemented), dashboard, MIS, or Google Drive
upload logic exists yet.

## Android Project

The real Flutter Android project (`android/`) has been generated with
`flutter create . --platforms=android --org com.tanfinet --project-name mobile_app`,
run against actual Flutter 3.50.0 / Dart 3.14.0 in a throwaway SDK
install in the session that set this up — it did **not** touch the
existing `lib/`, `test/`, or `pubspec.yaml`. Application ID:
`com.tanfinet.mobile_app`.

**Required Android permissions** — already added to
`android/app/src/main/AndroidManifest.xml`, for `image_picker`'s camera
capture and `geolocator`'s GPS reads:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

Two files `flutter create` generates are deliberately **not** committed
(see `android/.gitignore`, which is the current stock Flutter template,
unmodified): `android/gradlew`/`gradlew.bat`/`gradle-wrapper.jar` (the
Flutter tool and Android Studio regenerate these as needed) and
`android/local.properties` (machine-specific SDK path) and
`GeneratedPluginRegistrant.java` (regenerated by every `flutter pub get`).
This is standard for Flutter projects, not an omission.

## Running

Requires the Flutter SDK (this project was verified against 3.50.0 —
any recent stable should work, given the `>=3.3.0 <4.0.0` Dart SDK
constraint) and, to actually run on a device/emulator, the Android SDK
and a running `backend` instance.

```bash
cd mobile_app
flutter pub get
flutter analyze
flutter test
flutter run   # requires a connected device/emulator; backend must be running
```

`flutter pub get`, `flutter analyze`, and `flutter test` have all been
run and pass — see the top-level report for exact output. One
environment-specific quirk to know about: running `flutter test` with
**no arguments** (or pointed at the whole `test/` directory) in the
sandboxed container used to set this up only discovered/ran
`test/app_test.dart` and showed odd duplicated progress lines, even
though it reported "All tests passed!" Passing all four test file paths
explicitly with `--concurrency=1` ran all 15 tests cleanly with correct
names and no duplication — this looked like a concurrent-isolate
output-interleaving quirk tied to that specific container, not a defect
in the test files (each one also passed individually, standalone, with
default settings). If plain `flutter test` behaves oddly on a real
machine too, fall back to:

```bash
flutter test --concurrency=1 \
  test/app_test.dart \
  test/features/auth/auth_controller_test.dart \
  test/features/location_selection/pop_selection_controller_test.dart \
  test/features/pm_visit/pm_visit_controller_test.dart
```

`flutter analyze` reports 7 **informational** (not warning/error) notices
that `package:flutter/material.dart` is deprecated in favor of a new
`package:material_ui/material_ui.dart` (a very recent, still-external
pub.dev package introduced after Flutter 3.47 — not bundled with the
SDK). This is a genuine, current notice, not a mistake, but migrating
to it is a significant, still-emerging ecosystem shift that was out of
scope here; `flutter analyze --no-fatal-infos` exits 0, confirming zero
actual errors or warnings.

None of the native camera/GPS/SQLite code paths have been exercised on
a real device or emulator — only `flutter pub get` (dependency
resolution), `flutter analyze` (static analysis), and `flutter test`
(pure-Dart logic tests with fakes, no platform channels) were run. An
actual APK build/run needs the Android SDK, which was not installed
(out of scope for this step — see the top-level report).
