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

### Required Android permissions (add once `android/` is generated)

`image_picker`'s camera capture and `geolocator`'s GPS reads need
runtime permissions that belong in `android/app/src/main/AndroidManifest.xml`,
which does not exist yet in this hand-written skeleton (see "Running"
below). Once `flutter create .` generates it, add:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

Without these, the camera and GPS calls in this module will fail or be
silently denied at runtime on a real device/emulator — this has not
been verified in this session since no Flutter/Android toolchain is
available here.

No geofencing, offline *sync* (as opposed to offline *storage*, which
is implemented), dashboard, MIS, or Google Drive upload logic exists
yet.

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
this development session — see the top-level report for why. This
matters more than usual for this module: `image_picker`, `geolocator`,
`sqflite`, `path_provider`, and `path` were added to `pubspec.yaml` by
hand (version constraints chosen from general knowledge of these
packages, not verified against pub.dev or resolved here), and none of
the native camera/GPS/SQLite code paths have been exercised on a real
device or emulator.

Note: this skeleton was hand-written (no `flutter create` available in this
environment), so platform runner folders (`android/`, `ios/`) do not exist
yet. Running `flutter create .` inside `mobile_app/` on a machine with the
Flutter SDK will generate them without touching the existing `lib/` or
`pubspec.yaml` — recommended as the first action in the next step, before
any camera/GPS code is added.
