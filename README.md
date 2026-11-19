# TANFINET Geo-Tagged Fortnightly POP PM Monitoring System

A system for field engineers to perform and record fortnightly Preventive
Maintenance (PM) visits at TANFINET POP sites, with mandatory geo-tagged
photo evidence, offline capture, and centralized compliance tracking.

## System Overview

The system has two main components:

1. **`mobile_app/`** — Flutter (Android-first) field app used by engineers to:
   - Log in
   - Select District → Block → GP → POP
   - Capture 5 mandatory live photographs per visit (POP Rack, UPS & Battery,
     Busbar, Earth Pit Chamber, Earth Pit Open with Rod)
   - Capture GPS location + accuracy for every photo (no geofence
     validation — see "Current Status" below)
   - Work fully offline and sync later
2. **`backend/`** — Python FastAPI service that:
   - Authenticates engineers
   - Stores District/Block/GP/POP master data
   - Stores PM visit records (GPS, timestamps, photo metadata, Google Drive
     links)
   - Exposes district-wise/engineer-wise/POP-wise compliance dashboard data
     (now with a mobile UI too)
   - Exports a Monthly MIS report as a real downloadable CSV/Excel file

A web admin dashboard will be added in a later phase once the mobile app and
backend are functional.

## Technology Stack (locked)

| Layer | Technology |
|---|---|
| Mobile app | Flutter / Dart, Android-first, clean modular architecture |
| Backend | Python, FastAPI, PostgreSQL, REST API |
| Photo storage | Google Drive API (no Firebase) |
| Visit/metadata storage | PostgreSQL (GPS, timestamps, photo metadata, Drive links) |

Google Drive folder convention for the 5 PM photographs (see
`backend/README.md`, "Google Drive Upload", for full detail):

```
TANFINET PM Monitoring/
└── <District>/
    └── <Block>/
        └── <GP>/
            └── <POP code>/
                └── PM Visits/
                    └── <YYYY-MM-DD>/
                        └── <Visit ID>/
                            └── <PM visit photographs>
```

## Repository Structure

```
PM-activity-app-apk-/
├── mobile_app/     # Flutter app (see mobile_app/README.md)
├── backend/        # FastAPI service (see backend/README.md)
├── docs/
│   └── data-model.md
├── .gitignore
└── README.md
```

## Current Status

**Employee Login is implemented** (Flutter login screen + profile
display, FastAPI `/auth/login` endpoint, `Employee` data model). It uses
a development/test authentication mode (Employee ID + mobile number, no
OTP) designed to be swapped for OTP-based auth later without changing
the screens or endpoint — see `backend/README.md` ("Auth design").

**The issued JWT is now verified on every protected endpoint.**
`/locations/*` and `/visits/{id}/sync` require a valid
`Authorization: Bearer <token>` — the backend rejects a missing,
malformed, expired, or wrongly-signed token (or one for an unknown/
inactive employee) with 401 before processing the request; `/health`
and `/auth/login` remain intentionally public. See `backend/README.md`
("Protected endpoints (JWT verification)").

**POP Selection is implemented** (Flutter cascading District → Block →
GP → POP screen, FastAPI `/locations/*` endpoints, `District`/`Block`/
`GramaPanchayat`/`Pop` data models).

**POP has no latitude/longitude/geofence data, by design.** The official
POP coordinate master data has not been supplied yet, so none of the
code, seed data, or API responses use real or fake coordinates. POP
geofence validation is deferred until that data exists — see
`docs/data-model.md` ("POP Geo-Coordinates — Deferred"). Per-photo GPS
capture for PM visits is unaffected and still planned for a later module.

**PM Photo Capture is implemented** (Flutter "Start PM Visit" checklist
screen: device-camera-only capture, Retake/Confirm review, per-photo
live GPS, local SQLite storage for offline use). No geofence check is
performed anywhere — POP coordinates still don't exist (see above).

**GPS Watermark is implemented.** Every confirmed photo's exact capture
GPS fix (never POP coordinates, never fake) is burned as visible text —
TANFINET, POP ID, category, date, time, latitude, longitude, accuracy —
into a copy of the photo, in a consistent bottom banner that doesn't
cover the subject, for all 5 categories alike. The original photo is
kept alongside, untouched. If GPS can't be obtained, the photo is never
confirmable — see `docs/data-model.md` ("GPS Watermark").

**Offline Storage & Synchronization (foundation) is implemented.**
Every visit (Employee ID, District/Block/GP/POP, start time, sync
status) and all 5 photo records (original + watermarked paths, GPS,
upload status) live in on-device SQLite from the moment they're
captured — fully offline, surviving app restarts, and resumable if the
app is closed mid-visit. Once all 5 photos are confirmed, the visit
becomes **Pending Sync** automatically; "Sync Now" detects connectivity
and attempts a real sync pipeline (`SyncManager`).

**Google Drive Upload is implemented.** The Flutter app never holds
Google credentials: it sends the 5 **watermarked** photos (never the
plain originals, which stay device-local) plus visit/photo metadata to
the backend's `POST /api/v1/visits/{id}/sync`, and only the backend
authenticates to Google Drive and performs the upload, under the
District/Block/GP/POP/PM Visits/`<date>`/`<visit id>` folder structure
above, with deterministic file names
(`<POP code>_<CATEGORY>_<date>_<time>.jpg`) and idempotent retries (an
existing folder/file is reused, never duplicated). A failed upload
marks the visit `SYNC_FAILED` without touching any local data — see
`docs/data-model.md` ("Google Drive Upload") and `backend/README.md`
("Google Drive Upload" / "Google Drive Configuration") for the API,
folder/metadata detail, and the service-account setup the company
still needs to provide. **No real Google Drive account has been used
to test this** — see the top-level report for exactly what was and
wasn't verified.

**PM Visit Submission and Validation is implemented.** The visit
lifecycle now runs Draft → In Progress → Ready for Submission →
Pending Sync → Syncing → Synced → Submitted (with a Sync Failed branch,
retry-safe). A new Review & Submit screen shows the employee/location
summary, a ✓/✗ checklist of all 5 mandatory photos (with a thumbnail
and full-size preview of each), and the live sync status; Submit is
disabled unless every mandatory photo exists and is valid (category,
timestamp, plausible GPS, original path, watermarked path — **not**
geofence validation, and **not** checked against any POP coordinate,
which still doesn't exist). Submission reuses the existing
`SyncManager`/`GoogleDriveUploadService` pipeline unchanged — no second
upload path was created. Offline submission queues the visit as
Pending Sync; a failed Drive upload marks it Sync Failed with a visible
Retry action and never deletes local evidence; a rapid double-tap or
resubmitting an already-submitted visit never triggers a second upload
— see `docs/data-model.md` ("PM Visit Submission and Validation") for
the full lifecycle and validation rules.

**District/Engineer/POP-wise Dashboard is implemented, backend and
mobile UI.** `GET /api/v1/dashboard/districts`, `/engineers`, and
`/pops/{pop_id}/visits` report fortnightly compliance — a POP/engineer
is "compliant" only if all 5 mandatory categories were actually synced
for a visit, computed from a minimal `PmVisit`/`PmPhoto` record the
backend persists on a successful Drive sync (see `docs/data-model.md`,
"Backend PmVisit / PmPhoto"), and distinguishes a POP with *any* synced
visit this fortnight ("completed") from one with none ("pending") —
see `docs/data-model.md` ("Completed vs pending") for exactly what
that does and doesn't mean. Protected by the same JWT check as
`/locations/*`. The Flutter app's new `DashboardScreen` (via
`ProfileScreen`'s "View Dashboard" button) and `PopVisitHistoryScreen`
consume these endpoints directly — no mock data, no fortnight/
compliance math reimplemented client-side. A separate **web** admin
dashboard remains a later phase — see `backend/README.md` and
`mobile_app/README.md` ("Dashboard") for the endpoints, the mobile
screens, and the fortnight definition chosen.
**Widget- and real-network-level UI verification is done** (15
`testWidgets` tests render the real widget tree, including a real
scroll gesture, and caught/fixed one real overflow bug on a narrow
screen; separately, the real unmodified Flutter networking code was
also run via `dart run` against a real backend server process over a
real socket and worked correctly end to end). **A real Android
device/emulator pass has not been done** — this environment has no
Android SDK, no AVD images, and no computer attached via Remote
Control that could serve as one; this is explicitly reported as a
remaining limitation, not claimed as done — see `mobile_app/README.md`
("Dashboard UI verification") for the full PASS/BLOCKED breakdown and
the manual steps to run that pass.

**Monthly MIS / Excel export is implemented, backend and mobile UI.**
`GET /api/v1/mis/export?year=&month=&format=csv|xlsx` returns a real
downloadable file: one row per synced visit that month, plus a
`Pending` row per unvisited active POP, with Visit Date, Employee,
District/Block/GP/POP, Visit Status, Category Compliance, Overall
Compliance, Sync Status, and timestamps — reusing the exact same
`PmVisit`/`PmPhoto` data and compliance logic the Dashboard already
uses, filterable by the same geographic hierarchy plus employee — see
`backend/README.md` and `docs/data-model.md` ("Monthly MIS / Excel
Export") for the full column list and its one documented limitation
(Sync Status currently always mirrors Visit Status). The Flutter
app's `DashboardScreen` now has a "Download MIS Report" AppBar action
that calls this exact endpoint (`format=xlsx`, current device month)
over the same JWT session as every other request, and saves the file
to on-device app storage with clear loading/success/error feedback —
see `mobile_app/README.md` ("Download MIS Report") for the full
design and its one remaining device-only limitation (confirming the
saved file's real-device discoverability).

No geofencing has been implemented — it remains deferred until
official POP coordinate master data is supplied (see "POP
Geo-Coordinates — Deferred" in `docs/data-model.md`). See
`mobile_app/README.md` and `backend/README.md` for details and how to
run each part.

**The Flutter Android project exists.** `mobile_app/android/` was
generated for real with `flutter create .` (Flutter 3.50.0 / Dart
3.14.0), not hand-written, and the required Android permissions
(`CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
`ACCESS_NETWORK_STATE`) are set in its manifest. `flutter pub get`,
`flutter analyze` (0 errors/warnings), and `flutter test` (115/115
passing) have all been run and verified, alongside the backend's own
`pytest` suite (92/92 passing) — see `mobile_app/README.md` and
`backend/README.md` for exact commands and which tests are genuinely
real versus fake-backed.
