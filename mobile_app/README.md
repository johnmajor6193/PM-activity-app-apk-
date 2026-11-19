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
│   ├── network/              # ApiConfig (backend base URL), AuthSession (in-memory JWT holder, see Protected endpoints below)
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
│   ├── pm_visit/             # 5 mandatory photos, per-photo GPS, GPS watermark, offline storage + sync + Google Drive upload + submission/validation (implemented; no geofence yet)
│   │   ├── data/              # Camera/Location/Watermark/Connectivity services, SyncManager, GoogleDriveUploadService (calls the backend), NotImplementedDriveUploadService, local_database.dart (sqflite), SqflitePmVisitRepository
│   │   ├── domain/            # PmVisitRepository + DriveUploadService interfaces, PmVisit/PmPhotoRecord/GpsReading/PhotoCategory/VisitSyncStatus (+ GpsReadingValidation/PmPhotoRecordValidation extensions)
│   │   └── presentation/      # PmVisitController (submitVisit), PmVisitScreen, PmVisitSubmissionScreen (Review & Submit)
│   ├── sync/                 # reserved (e.g. background/scheduled sync) - the sync queue, state model, and Drive upload all ended up living in pm_visit/ instead, see above
│   └── dashboard/            # District/Engineer/POP-wise compliance dashboard (implemented; see "Dashboard" below)
│       ├── data/              # DashboardApiClient, DashboardRepositoryImpl
│       ├── domain/            # DashboardRepository interface, DistrictCompliance/PopPeriodStatus/EngineerPerformance/PopVisitEntry, DashboardFailure
│       └── presentation/      # DashboardController, DashboardScreen, PopVisitHistoryController, PopVisitHistoryScreen
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

**The JWT the backend returns is now actually used.** The backend's
`/locations/*` and `/visits/{id}/sync` endpoints verify a Bearer token
on every request (see `backend/README.md`, "Protected endpoints (JWT
verification)") — previously issued on login but never checked
anywhere. `DevLoginAuthRepository` stores the `access_token` from a
successful login in `AuthSession`
(`lib/core/network/auth_session.dart`) — in memory only, never written
to disk and never logged — and `LocationApiClient` /
`GoogleDriveUploadService` now attach it as `Authorization: Bearer
<token>` on every request. The login screen, its request/response
shape, and `AuthController` are otherwise unchanged.

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
- That exact GPS fix is immediately burned as a **visible watermark**
  into a copy of the photo (`WatermarkService`, pure Dart via
  `package:image` — no platform channel): `TANFINET`, POP ID, the
  category label, capture date + time, latitude, longitude, and GPS
  accuracy, in a dark banner anchored to the bottom edge only, the same
  layout for every category. The original photo is kept too, untouched.
- The review sheet shows the **watermarked** photo (not the plain
  original) with the same GPS values as text underneath, so the engineer
  sees exactly what will be saved, with **Retake** (discards both
  files, category stays Pending) and **Confirm** (saves both files,
  category becomes Completed).
- **No geofence check happens anywhere in this flow.** The captured
  GPS is stored and shown as-is; it is never compared against a POP
  coordinate, because POP coordinates don't exist yet (see POP
  Selection above).
- **If GPS can't be obtained** (location services off, permission
  denied), no photo reaches the review step at all — no watermark is
  attempted, no fake coordinates are substituted, the category stays
  Pending, and the failure message is shown directly on the checklist
  screen. The only way to complete a category is a real GPS fix.
Everything above works with **zero network calls**, and a visit's data
(including which employee, district, block and GP it belongs to) and
its confirmed photos (original + watermarked, each) are written to
SQLite as they're captured — see
`lib/features/pm_visit/data/local_database.dart` and
`docs/data-model.md` ("PM Visit & PM Photo — Local (On-Device)
Implementation" and "GPS Watermark"). **Closing and reopening the app
mid-visit resumes it** instead of starting a duplicate: opening the
same POP again finds the incomplete visit (`PmVisitRepository.
getResumableVisit`) and continues it, with already-confirmed photos
shown as Completed.

**Offline Storage & Synchronization (foundation) is implemented.** The
moment the 5th photo is confirmed — offline, no button, no network
call — the visit's status becomes **Ready for Submission**
automatically (`VisitSyncStatus`: `draft` → `inProgress` →
`readyForSubmission` → `pendingSync` → `syncing` →
`synced`/`syncFailed` → `submitted`; see `docs/data-model.md`). A
status banner on `PmVisitScreen` always shows the current one. Once
complete, the button changes to **"Review & Submit"**, which opens
`PmVisitSubmissionScreen` — see "PM Visit Submission and Validation"
below for what happens there.

**Google Drive Upload is implemented — via the backend, never
directly from this app.** `GoogleDriveUploadService` (the default
`DriveUploadService`) sends the 5 **watermarked** photos (never the
plain originals, which stay on the device per the offline-storage
design above) plus visit/photo metadata to the backend's
`POST /api/v1/visits/{visitId}/sync`. **This app holds no Google
credentials of any kind** — see `backend/README.md` ("Google Drive
Upload") for the folder structure
(`TANFINET PM Monitoring/<District>/<Block>/<GP>/<POP code>/PM
Visits/<date>/<visit id>/`), file naming, and idempotent-retry
behavior, all implemented server-side. If the backend reports failure
(including "Google Drive is not configured on this server" — the
default until the company provides service-account credentials — see
`docs/data-model.md`), `SyncManager` marks the visit `SYNC_FAILED` with
that message. `NotImplementedDriveUploadService` is still available,
importable, and passable explicitly (e.g. to develop against this app
with no backend reachable at all) — it just isn't the default anymore.

A failed (or skipped, for no connection) sync attempt **never deletes
or modifies any local photo or visit data** — only the `status` column
changes — so the visit remains fully intact and Submit/Retry can be
tapped again later, exactly the same way.

**PM Visit Submission and Validation is implemented.**
`PmVisitSubmissionScreen` ("Review & Submit") shows Employee ID/name,
District, Block, GP, POP ID, visit date/time, a ✓/✗ checklist of all 5
mandatory categories (each with a thumbnail of the watermarked evidence
photo, tappable for a full preview), and the current sync status. The
**Submit** button (relabeled **Retry Submission** after a failure) is
only enabled when every mandatory photo exists and is valid — category,
timestamp, a plausible GPS fix, the original path, and the watermarked
path (`PmPhotoRecordValidation.isValidForSubmission`,
`GpsReadingValidation.isPlausible`). This is a basic sanity check on the
GPS values themselves, **not** geofence validation — it never compares
against a POP coordinate, since POP coordinates still don't exist.

Tapping Submit calls `PmVisitController.submitVisit()`, which drives
the visit through `readyForSubmission` → `pendingSync` → `syncing` →
`synced` → `submitted` (or `syncFailed`) using the **existing, unchanged**
`SyncManager`/`GoogleDriveUploadService` pipeline — no second upload
implementation was created. No connection at submit time leaves the
visit `pendingSync` with an explanatory message, retained fully
locally, to synchronize later. A failed Drive upload marks it
`syncFailed` with a visible Retry action, never deleting local
evidence. A guard set synchronously before the first `await` blocks a
rapid double-tap or a resubmit of an already-`submitted` visit from
ever triggering a second Drive upload — see `docs/data-model.md` ("PM
Visit Submission and Validation") for the full lifecycle and test list.

**Dashboard is implemented.** `DashboardScreen` (opened via the new
"View Dashboard" button on `ProfileScreen`) has two tabs — Districts
and Engineers — for a selected fortnight, reading the backend's
already-implemented `GET /dashboard/districts`/`/engineers` endpoints
directly; no mock data anywhere, and no fortnight/compliance math is
re-implemented in Dart (the backend's `fortnight_bounds` stays the one
place that logic lives — "previous"/"next fortnight" navigation just
reuses the `period_start`/`period_end` the backend already returned).
The Districts tab expands into a per-POP completed/pending breakdown
(each POP's status, and, when incomplete, exactly which mandatory
categories are missing by name — reusing the existing
`PhotoCategory.label` mapping, not a second one). Tapping a POP (or
the new "View Visit History" button on POP Selection's detail card)
opens `PopVisitHistoryScreen`: the POP's District › Block › GP
context, read from the existing, unchanged
`GET /locations/pops/{id}` endpoint, plus every synced visit for that
POP with its own compliance badge and category breakdown, via
`GET /dashboard/pops/{id}/visits`. Every dashboard request reuses the
same `AuthSession`-held JWT as every other protected call — no new
login flow, no new token handling. See `docs/data-model.md`
("Dashboard UI (mobile)") for the full design notes, including the one
known display-precision limitation (sync timestamps can show in the
wrong timezone on this dev/test SQLite setup specifically — a
pre-existing backend/storage nuance, not something this module
introduced).

### Dashboard UI verification

A final verification pass checked `DashboardScreen`/
`PopVisitHistoryScreen` against the full requirement list (login →
dashboard navigation, District/Engineer rendering, POP drill-down,
completed-vs-pending clarity, category breakdown, GP/Block/District
context, visit date/time, loading/empty/error states, layout on a
narrow screen, and that PM Visit/GPS/photo/watermark/offline/sync were
unaffected).

**No Android device or emulator exists in this environment** —
`flutter doctor` reports no Android SDK, `flutter emulators` finds no
AVD images, and `flutter devices` only lists a Linux desktop target
(missing GTK3, won't actually build) and Chrome; this project was only
ever scaffolded for Android (`flutter create . --platforms=android`),
so there is no `web/` or `linux/` directory to run on either. A real
on-device/emulator pass **has not been done** and is explicitly called
out here rather than assumed to have passed.

What **was** done instead, as the strongest verification available
without a device: 14 new `testWidgets` tests
(`test/features/dashboard/dashboard_screen_test.dart`,
`pop_visit_history_screen_test.dart`,
`test/features/auth/profile_screen_dashboard_navigation_test.dart`)
that pump the real widget trees — with real fake-backed data, a
narrow (360×800) test surface approximating a normal phone width, and
`tester.takeException()` checked after every render — rather than
only exercising the controllers. **This is real verification, not a
substitute for one**: Flutter's test framework genuinely lays out and
renders the widgets, so a `RenderFlex` overflow is a real, measured
layout failure, not a guess — and it caught one: `_OverallSummaryCard`'s
header row overflowed by 115–159px on a 360px-wide screen because its
title `Text` had no `Expanded`/`Flexible` wrapper. **Fixed** (wrapped
in `Expanded` with `TextOverflow.ellipsis`); re-run and now passes at
that width. `PopVisitHistoryScreen` showed no overflow at the same
width. What a widget test still cannot verify: real touch/scroll
physics, real keyboard overlap, real status bar/safe-area insets, real
screen density variety, and real network latency — those need an
actual device/emulator pass.

To make this injection possible, `DashboardScreen` and
`PopVisitHistoryScreen` each gained an optional `controller`
constructor parameter (default `null`, behavior unchanged when
omitted) — the same dependency-injection pattern every controller in
this app already uses, just threaded one level up to the screen. This
is a testability addition only, not a business-logic change; confirmed
by `flutter analyze` (unchanged, 0 errors) and the full regression
suite below.

**A second verification round went further**, still without a
device: a real `uvicorn` process (the actual FastAPI app, not
`TestClient`) was started on a real loopback socket, and (a) `curl`
exercised real login, real `/locations/*`/`/dashboard/*` calls with a
real JWT, and a real 401 for no/invalid tokens; (b) the real,
unmodified `DashboardApiClient`/`DashboardRepositoryImpl`/
`AuthSession` production Dart code (not a test double) was run via
`dart run` against that same real server and correctly logged in,
fetched and parsed real district/engineer/visit-history data, and
correctly threw `DashboardFailure` for an anonymous request. This is
genuine real-API/real-network verification of the server and the
Flutter networking code together — it is **not** a substitute for
running on a real Android device (no real mobile network stack, no
real device-to-emulator-host routing, no `10.0.2.2` alias involved).
A real `tester.drag()` scroll gesture was also added
(`dashboard_screen_test.dart`) and confirmed the district list
genuinely scrolls to reveal off-screen content on a short viewport —
real `Scrollable` behavior, though still not a real finger on real
glass.

**Verification summary against the 11-item checklist** (`PASS` =
genuinely verified by one of the methods above; `BLOCKED` = requires
an actual Android device/emulator this environment does not have):

| # | Item | Result |
|---|---|---|
| 1 | Dashboard loading and navigation | PASS (widget test) |
| 2 | District compliance | PASS (widget test + real server/client) |
| 3 | Engineer performance | PASS (widget test + real server/client) |
| 4 | POP visit history | PASS (widget test + real server/client) |
| 5 | Completed/pending status | PASS (widget test + real server/client) |
| 6 | Category-wise photo compliance | PASS (widget test) |
| 7 | GP/Block/District context | PASS (widget test + real server/client) |
| 8 | Visit date/time | PASS (widget test); display-precision caveat above still applies |
| 9 | Loading/empty/error states | PASS (widget test + a real 401 over real HTTP) |
| 10 | Mobile layout, scrolling, safe areas, keyboard | PARTIAL — layout (one bug found+fixed) and scrolling PASS at widget-test level; safe-area insets and real touch remain BLOCKED (no device); keyboard is N/A (neither screen has a text field) |
| 11 | Real API/network behavior | PARTIAL — real server + real Flutter client verified over a real socket (PASS); real mobile network/device HTTP stack remains BLOCKED (no device) |

**Manual verification steps for a real Android device/emulator**
(none of this has been run on one yet):

1. `flutter run` on a real device/emulator with the backend reachable
   (`--dart-define=API_BASE_URL=http://<host>:8000` if not using the
   emulator default). Log in as `ENG001` / `9876543210`.
2. On `ProfileScreen`, tap **"View Dashboard"** — confirm `DashboardScreen`
   opens with no visible delay/flicker and the status bar/app bar render
   correctly.
3. **Districts tab**: confirm the overall summary card and each
   district card show a percentage, and that long district/POP names
   don't clip or overflow (rotate to landscape too).
4. **Engineers tab**: confirm each engineer's visits-synced/compliant
   ratio renders, including an engineer with 0 visits.
5. Tap a POP row: confirm `PopVisitHistoryScreen` opens showing the
   District › Block › GP breadcrumb and Active/Inactive status.
6. Confirm a POP with no visit this fortnight shows **"Pending"**
   clearly (grey/hourglass), a POP with a full 5/5 visit shows
   **"Completed"** + compliant (green/check), and a POP with a partial
   visit shows **"Completed"** but incomplete (orange) with the exact
   missing category names listed.
7. On the visit history list, confirm each visit shows its category
   chips (✓ green for present, ✗ grey for missing), its `Visit date:`
   (date only — there is no visit-level time, by design, see
   `docs/data-model.md`), and its `Synced:` timestamp.
8. Turn off Wi-Fi/data, pull down to refresh on either tab: confirm a
   clear, non-crashing error message appears (not a blank screen or an
   unhandled exception).
9. Turn the connection back on, refresh, confirm the real data reloads.
10. From `PopSelectionScreen`'s POP detail card, tap **"View Visit
    History"**: confirm it opens the same history screen for that POP.
11. Go back through every PM Visit screen (capture a photo, confirm,
    retake, submit) exactly as before this module — confirm nothing
    about GPS capture, the watermark, offline storage, or sync status
    looks or behaves differently.

No geofencing or MIS export exists yet.

## Android Project

The real Flutter Android project (`android/`) has been generated with
`flutter create . --platforms=android --org com.tanfinet --project-name mobile_app`,
run against actual Flutter 3.50.0 / Dart 3.14.0 in a throwaway SDK
install in the session that set this up — it did **not** touch the
existing `lib/`, `test/`, or `pubspec.yaml`. Application ID:
`com.tanfinet.mobile_app`.

**Required Android permissions** — already added to
`android/app/src/main/AndroidManifest.xml`, for `image_picker`'s camera
capture, `geolocator`'s GPS reads, and `connectivity_plus`'s
connectivity checks:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

(`connectivity_plus` declares `ACCESS_NETWORK_STATE` in its own plugin
manifest too, so Android's manifest merger would add it either way —
it's declared here explicitly for the same documentation reasons as
the other three.)

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
sandboxed container used to set this up only discovered/ran a subset
of the test files and showed odd duplicated/missing progress lines,
even though it reported "All tests passed!" Passing every test file
path explicitly with `--concurrency=1` ran all of them cleanly with
correct names and no duplication — this looked like a concurrent-isolate
output-interleaving quirk tied to that specific container, not a defect
in the test files (each one also passed individually, standalone, with
default settings). If plain `flutter test` behaves oddly on a real
machine too, fall back to:

```bash
flutter test --concurrency=1 \
  test/app_test.dart \
  test/features/auth/auth_controller_test.dart \
  test/features/location_selection/pop_selection_controller_test.dart \
  test/features/pm_visit/pm_visit_controller_test.dart \
  test/features/pm_visit/watermark_service_test.dart \
  test/features/pm_visit/sqflite_pm_visit_repository_test.dart \
  test/features/pm_visit/sync_manager_test.dart \
  test/features/pm_visit/google_drive_upload_service_test.dart \
  test/features/dashboard/dashboard_api_client_test.dart \
  test/features/dashboard/dashboard_repository_impl_test.dart \
  test/features/dashboard/dashboard_controller_test.dart \
  test/features/dashboard/pop_visit_history_controller_test.dart \
  test/features/dashboard/dashboard_screen_test.dart \
  test/features/dashboard/pop_visit_history_screen_test.dart \
  test/features/auth/profile_screen_dashboard_navigation_test.dart
```

Two test files in this project need no fakes at all, because what they
test has no platform channel:

- `watermark_service_test.dart` writes a real synthetic image to a
  real temp file, runs the real `WatermarkService`, decodes the real
  output, and asserts on actual pixels (unchanged above the banner,
  visibly different inside it) and exact watermark text.
- `sqflite_pm_visit_repository_test.dart` runs the real
  `SqflitePmVisitRepository` against a real SQLite database — via
  `sqflite_common_ffi`, which loads the system's native `sqlite3`
  through FFI instead of the `sqflite` plugin's Android/iOS platform
  channel. `PmVisitLocalDatabase.withPath(...)` (a `@visibleForTesting`
  factory) points it at a temp file instead of asking `path_provider`
  for one, since `path_provider` itself needs a platform channel these
  tests don't have. Real schema, real SQL, real row mapping.

`sync_manager_test.dart` tests `SyncManager`'s own orchestration logic
(status transitions, retry, "don't touch anything without a
connection") against fakes for the repository/connectivity/Drive
pieces — `SyncManager` itself has no platform dependency, so there's
nothing "real" underneath to swap in here.

`google_drive_upload_service_test.dart` tests the real HTTP
request-building logic (which files get attached, that only the
watermarked content is sent and never the original's, the exact
metadata fields) against a fake transport
(`package:http`'s `MockClient`) — there is no real backend or Google
Drive involved; see `backend/tests/test_drive_sync.py` for the
backend-side endpoint tests (folder path generation, file naming,
upload success/failure/retry/idempotency), which also use a fake
(`FakeDriveUploadService`), never real Google credentials.

Every other test file fakes the camera/GPS boundaries specifically,
because `image_picker` and `geolocator` do need a real device/emulator.

`flutter analyze` reports 13 **informational** (not warning/error) notices
that `package:flutter/material.dart` is deprecated in favor of a new
`package:material_ui/material_ui.dart` (a very recent, still-external
pub.dev package introduced after Flutter 3.47 — not bundled with the
SDK). This is a genuine, current notice, not a mistake, but migrating
to it is a significant, still-emerging ecosystem shift that was out of
scope here; `flutter analyze --no-fatal-infos` exits 0, confirming zero
actual errors or warnings.

None of the native camera/GPS code paths have been exercised on a real
device or emulator — only `flutter pub get` (dependency resolution),
`flutter analyze` (static analysis), and `flutter test` were run. Of
`flutter test`, the watermark image manipulation and the SQLite
repository are genuinely real (see above); everything that touches
`image_picker`, `geolocator`, or `connectivity_plus` is tested against
hand-written fakes, not the real plugins — those three specifically
need a real device/emulator to verify. An actual APK build/run needs
the Android SDK, which was not installed (out of scope for this step —
see the top-level report).

**No real Google Drive upload has been tested anywhere** — not from
this app, and not from the backend. `GoogleDriveUploadService` here is
tested only against a mocked HTTP transport, and the backend's own
Drive integration is tested only against `FakeDriveUploadService`
(both described above). A real end-to-end test needs a running backend
with `GOOGLE_SERVICE_ACCOUNT_FILE` configured — see `backend/README.md`
("Google Drive Configuration") for exactly what the company needs to
provide.
