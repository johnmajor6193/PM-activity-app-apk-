# Data Model — TANFINET POP PM Monitoring System

This document defines the core entities and relationships the backend
(PostgreSQL, via FastAPI) stores. Employee, District, Block, GP, and POP
are implemented; PMVisit and PMPhoto are still planning-only.

## POP Geo-Coordinates — Deferred, Not Faked

The official POP latitude/longitude master data has not been supplied
yet. Until it is:

- `Pop` has **no** `latitude`, `longitude`, or `geofence_radius_m`
  columns, and the API/app never seed or generate placeholder values
  for them.
- **POP geofence validation is not implemented.** `PMVisit.within_geofence`
  below remains a planned field, blocked on this data.

This does **not** affect per-photo GPS: the later PM visit/photo capture
module still must capture live GPS lat/long for every photograph, burn
it into the visible watermark, store it in the database
(`PMPhoto.gps_lat`/`gps_lng`/`gps_accuracy_m`), and preserve original
photo GPS metadata where supported. That is independent of whether a
POP's own registered coordinates exist.

## Entity Overview

```
Employee
   └── performs ──> PMVisit ──> belongs to ──> POP
                       │                          │
                       │                          ├── belongs to ──> Block
                       └── has 5 ──> PMPhoto       │                   │
                                                    │                   └── belongs to ──> District
                                                    └── belongs to ──> GP (Gram Panchayat)
                                                                           │
                                                                           └── belongs to ──> Block
```

Location hierarchy: **District → Block → GP → POP** (each level is a
simple parent/child lookup table).

## 1. District — implemented

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| name | string | unique |

## 2. Block — implemented

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| district_id | FK → District | |
| name | string | |

## 3. GP / GramaPanchayat (Gram Panchayat) — implemented

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| block_id | FK → Block | |
| name | string | |

## 4. POP (Point of Presence) — implemented

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| gp_id | FK → GP | |
| pop_code | string | unique identifier used in the field |
| name | string, nullable | optional display name/details |
| is_active | bool | engineers select only active POPs by default |

**No latitude/longitude/geofence_radius_m** — see "POP Geo-Coordinates —
Deferred" above.

`district_id`/`block_id` are **not** denormalized onto `POP`; they are
resolved by joining up the GP → Block → District chain (see
`app/api/v1/endpoints/locations.py:get_pop`). This also resolves open
decision #2 below for POP; it remains open for `PMVisit`.

## 5. Employee — implemented

| Field | Type | Notes |
|---|---|---|
| id | int, PK | |
| employee_code | string | unique, used for login |
| name | string | |
| mobile_number | string | used for login (dev mode: ID + mobile match, no password) |
| assigned_district_name | string, nullable | plain string, **not** a `District` FK yet — see note below |
| is_active | bool | |

`assigned_district_name` is intentionally not linked to the new
`District` table yet. Employee Login was explicitly kept unchanged while
building POP selection; wiring it to a real `district_id` FK is left for
a later step. `role` and `password_hash` from the original plan were not
needed for the dev login mode and were dropped; revisit if/when OTP or
role-based access is added.

## 6. PMVisit — backend: planned; on-device: implemented (see #8)

Represents one fortnightly PM visit to a single POP.

| Field | Type | Notes |
|---|---|---|
| id | UUID, PK | |
| pop_id | FK → POP | |
| employee_id | FK → Employee | |
| visit_started_at | timestamp | device-local time, captured offline |
| visit_submitted_at | timestamp | when synced to server |
| visit_gps_lat | decimal | GPS at visit/check-in time |
| visit_gps_lng | decimal | |
| visit_gps_accuracy_m | decimal | |
| within_geofence | bool | **deferred** — needs POP `latitude`/`longitude`/`geofence_radius_m`, not available yet (see "POP Geo-Coordinates — Deferred") |
| sync_status | enum | `pending_sync`, `synced`, `sync_failed` |
| fortnight_period | string / date range | which fortnight this visit satisfies, for compliance tracking |

## 7. PMPhoto — backend: planned; on-device: implemented (see #8)

Exactly 5 rows per completed `PMVisit`, one per mandatory category.

| Field | Type | Notes |
|---|---|---|
| id | UUID, PK | |
| visit_id | FK → PMVisit | |
| category | enum | `pop_rack`, `ups_battery`, `busbar`, `earth_pit_chamber`, `earth_pit_open_rod` |
| captured_at | timestamp | device-local, from camera capture |
| gps_lat | decimal | GPS at moment of photo capture |
| gps_lng | decimal | |
| gps_accuracy_m | decimal | |
| local_file_path | string | on-device path before sync (offline queue) |
| drive_file_id | string, nullable | Google Drive file ID once uploaded |
| drive_file_link | string, nullable | shareable Drive link |
| drive_folder_path | string | e.g. `TANFINET PM Monitoring/<District>/<Block>/<GP>/<POP code>/PM Visits/<date>/<visit id>` — see "Google Drive Upload" below |
| upload_status | enum | `pending`, `uploaded`, `failed` |

Watermark (GPS + date/time burned into the image) is applied on-device at
capture time, before the file is queued for upload — the stored photo file
itself carries the visible watermark; `gps_lat`/`gps_lng`/`captured_at`
are also stored as structured metadata for querying and compliance checks.

## 8. PM Visit & PM Photo — Local (On-Device) Implementation

The PM Photo Capture module stores visits and photos **only on the
device** (SQLite, via `sqflite`) — there is no backend PMVisit/PMPhoto
table yet, no submission endpoint, and no cloud sync. This is
intentional: the mobile app must work fully offline, and the fields
below are deliberately a close match to the backend `PMVisit`/`PMPhoto`
plan above, so that wiring up sync later is a mapping exercise, not a
redesign.

Implementation: `mobile_app/lib/features/pm_visit/data/local_database.dart`.

**`pm_visits`** (one row per visit started on this device):

| Column | Type | Notes |
|---|---|---|
| id | TEXT, PK | generated on-device (not a backend ID — no backend row exists) |
| employee_id | TEXT | the logged-in engineer's Employee ID, threaded through from login |
| pop_id | INTEGER | the backend `POP.id` this visit is for |
| pop_code | TEXT | denormalized for display without a join |
| district, block, gp | TEXT | the POP's District/Block/GP names, denormalized from POP Selection at the moment the visit starts |
| started_at | TEXT (ISO 8601) | device-local timestamp |
| status | TEXT | the visit's offline-first sync lifecycle — see "Offline Storage & Synchronization" below |

**`pm_photos`** (one row per *confirmed* mandatory photo; retake
replaces the row for the same `(visit_id, category)`):

| Column | Type | Notes |
|---|---|---|
| visit_id, category | TEXT, TEXT — composite PK | `category` is one of `pop_rack`, `ups_battery`, `busbar`, `earth_pit_chamber`, `earth_pit_open_with_rod` |
| pop_id | INTEGER | |
| local_file_path | TEXT | the untouched original photo, exactly as the camera captured it |
| captured_at | TEXT (ISO 8601) | the moment the camera took the photo |
| gps_latitude, gps_longitude, gps_accuracy_m | REAL | a **fresh GPS fix taken for this specific photo**, not reused from visit start or any other photo. Not compared against any POP coordinate — no geofence check is performed anywhere in this module (see "POP Geo-Coordinates — Deferred" above) |
| upload_status | TEXT | `pending` / `uploaded` / `failed` — prepares for sync, but nothing sets it to anything but `pending` yet |
| watermarked_file_path | TEXT | the GPS-watermarked evidence copy — see "GPS Watermark" below. Populated for every photo confirmed from this point on; stays a nullable column since rows saved before this existed have none |
| drive_file_id, drive_file_link | TEXT, nullable | reserved for Google Drive upload; always `NULL` today |

What this deliberately does **not** do yet: upload anywhere, run a
geofence check, or submit the visit. Those are later modules; this
schema is shaped so adding them means filling in existing nullable
columns / adding sync logic, not changing what is captured today.

### GPS Watermark

Every confirmed photo gets a second file, `watermarked_file_path`,
produced by `mobile_app/lib/features/pm_visit/data/watermark_service.dart`
(pure Dart, via `package:image` — no platform channel, no camera/GPS
hardware involved in this step itself). `local_file_path` (the original)
is never modified.

- The watermark is generated from the **same `GpsReading` instance**
  captured for that photo (see `gps_latitude`/`gps_longitude`/
  `gps_accuracy_m` above) — not POP master coordinates, which don't
  exist, and not a separate/re-fetched reading. This is enforced
  structurally in `PmVisitController.capturePhoto`: one GPS fix is
  read, then passed to both the watermark call and the eventual
  `PmPhotoRecord`, so the two can't drift apart.
- Fixed content, in this order, identical for all 5 categories: `TANFINET`,
  `POP ID: <popCode>`, `<category label>`, `<date>  <time>`,
  `Lat: <lat>  Lng: <lng>`, `GPS Accuracy: ±<accuracy> m`.
- Burned into a dark semi-transparent banner anchored to the bottom
  edge only, sized to fit the text — it does not reach into the
  upper/central area where the inspected equipment is expected to be.
- If GPS capture fails (no fix, permission denied, location services
  off), no watermark is attempted and no photo reaches the review
  step at all: the category stays Pending, the failure is shown to the
  engineer, and nothing is confirmable for that category until a real
  GPS fix succeeds. No fake/placeholder coordinates are ever used.
- If watermarking itself fails (e.g. an undecodable image), the
  capture is discarded the same way — the category stays Pending.

### Offline Storage & Synchronization (foundation)

The app must work with no network connection: starting a visit,
capturing all 5 photos, GPS, and the watermark all happen with zero
network calls, and everything lands in the `pm_visits`/`pm_photos`
tables above — nothing is held only in memory. Closing and reopening
the app does not lose a visit: `PmVisitController.startVisit` looks for
an incomplete (LOCAL_ONLY) visit for the same POP via
`PmVisitRepository.getResumableVisit` and continues it, rather than
starting a duplicate.

**`pm_visits.status` — `VisitSyncStatus`** (implementation:
`mobile_app/lib/features/pm_visit/domain/entities/visit_sync_status.dart`):

| Value | Meaning |
|---|---|
| `localOnly` | Visit started; photos still being captured. Nothing to sync yet. |
| `pendingSync` | All 5 mandatory photos confirmed. Set automatically, offline, the moment the 5th is confirmed — no button press, no network call. |
| `syncing` | A sync attempt is in progress right now. |
| `synced` | Sync completed successfully. **Not reachable yet** — see below. |
| `syncFailed` | The most recent sync attempt failed. The visit and its photos are **never** deleted for this; it stays eligible for retry. |

**`SyncManager`** (`mobile_app/lib/features/pm_visit/data/sync_manager.dart`)
is the queue: `getVisitsEligibleForSync()` returns visits in
`pendingSync` or `syncFailed`; `syncVisit(visit)` is retry-safe —
`pendingSync`/`syncFailed` → `syncing` → `synced` (success) or back to
`syncFailed` (failure) — and only ever touches the `status` column,
never photos or other visit fields. If there's no connection
(`ConnectivityService`, via `connectivity_plus`), nothing is attempted
at all and the status is left exactly as it was. `trySyncPendingVisits()`
attempts every eligible visit; one failing does not stop the others.

`DriveUploadService` (`domain/services/drive_upload_service.dart`,
`Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos)`)
is what `SyncManager` calls to actually move photos somewhere. Two
implementations exist:

- `GoogleDriveUploadService` (`data/`) — **the default**. See "Google
  Drive Upload" below: it does not talk to Google Drive itself, it
  calls the backend.
- `NotImplementedDriveUploadService` (`data/`) — still present,
  importable, and passable explicitly (e.g. for developing against the
  app with no backend reachable at all); always throws.

Per-photo `upload_status` (`pending`/`uploaded`/`failed`, from the PM
Photo Capture module) is intentionally left alone by this module — it
stays `pending` for every photo; only the backend's response (via
`GoogleDriveUploadService`) and `SyncManager`'s visit-level `status`
reflect whether the upload actually happened.

## Google Drive Upload

**Architecture: the backend is the only thing that talks to Google
Drive.** The Flutter app never holds a Google service-account key or
any other Google credential. It sends the 5 **watermarked** photos
(`PmPhotoRecord.watermarkedFilePath` — never the plain originals,
which stay device-local per "GPS Watermark" above) plus visit/photo
metadata to the backend over HTTPS; the backend authenticates to
Google Drive and performs the actual upload.

```
Flutter (GoogleDriveUploadService)
   │  POST /api/v1/visits/{visit_id}/sync
   │  multipart/form-data: visit_metadata (JSON), photos_metadata (JSON), files[] (5 watermarked JPEGs)
   ▼
Backend (app/api/v1/endpoints/visits.py)
   │  validates visit_id/counts, builds the deterministic filename per photo
   ▼
GoogleDriveUploadService (backend interface, app/services/drive/base.py)
   │  GoogleDriveServiceAccountUploadService (real) │ NotConfiguredDriveUploadService │ FakeDriveUploadService (tests)
   ▼
Google Drive API (only the real implementation reaches here)
```

**Folder structure** (created/found as needed under
`GOOGLE_DRIVE_ROOT_FOLDER_NAME`, default `TANFINET PM Monitoring`):

```
TANFINET PM Monitoring/
└── <District>/
    └── <Block>/
        └── <GP>/
            └── <POP code>/
                └── PM Visits/
                    └── <YYYY-MM-DD>/
                        └── <Visit ID>/
                            └── (the 5 watermarked photos)
```

Each visit gets its own folder (`<Visit ID>`), under a date folder
(`visit_date`, derived from when the visit started), under the POP's
full District/Block/GP/POP-code path. Built by
`app/services/drive/naming.py:build_drive_folder_segments` (backend) —
a pure function, unit-tested directly.

**File naming** — deterministic and human-readable:
`<POP code>_<CATEGORY>_<YYYY-MM-DD>_<HHMMSS>.jpg`, e.g.
`POP-00125_POP-RACK_2026-11-17_172542.jpg`
(`app/services/drive/naming.py:build_drive_filename`, also
unit-tested). The POP code is sanitized to filesystem/Drive-safe
characters (`[^A-Za-z0-9_-]` → `-`).

**Idempotent, retry-safe uploads.** Before creating a folder or a file,
the backend looks for an existing one with the same name under the
same parent (a Drive `files.list` query). A retried sync for the same
visit — the normal case after a network failure — finds what already
made it to Drive and reuses it (reported back to the app as
`duplicate: true`) instead of creating a second copy. Nothing is ever
deleted, so a half-finished prior attempt is always safe to build on
top of.

**Per-photo metadata**, attached to each uploaded file via Drive's
`appProperties` (not just implied by the folder path): Visit ID,
Employee ID, POP ID, District, Block, GP, category, capture timestamp,
latitude, longitude, GPS accuracy.

**Expected state flow** (`VisitSyncStatus`, unchanged from "Offline
Storage & Synchronization" above — this module implements what makes
`synced` reachable, it doesn't change the state machine itself):

```
PENDING_SYNC → SYNCING → SYNCED           (upload succeeds)
PENDING_SYNC → SYNCING → SYNC_FAILED      (upload fails; retry later, nothing local is touched)
```

**Required configuration (from the company, not yet provided in this
environment):** a Google Cloud **service-account** JSON key with
access to Google Drive (typically via a Shared Drive, since service
accounts have no personal storage quota), set as
`GOOGLE_SERVICE_ACCOUNT_FILE` on the backend server — never committed
to this repository. See `backend/README.md` ("Google Drive
Configuration") for the exact steps. Until it's set, every sync
attempt gets a clean `SYNC_FAILED` with a "Google Drive is not
configured" message — never a fake success.

**Real Google Drive upload has not been tested in this environment** —
no service-account credentials or reachable Google Drive were
available. What has been verified is the full pipeline against
`FakeDriveUploadService` (backend) and a mocked HTTP transport
(Flutter) — see the top-level report for the exact test list.

## Compliance / Reporting (derived, not stored directly)

These are computed from the above, to support the dashboards and MIS
export planned for a later phase:

- **Fortnightly compliance**: for each POP, was a valid `PMVisit` (5/5
  photos, within geofence) submitted in each fortnight period? The
  geofence part is blocked on POP coordinates (see above); photo-count
  and timing checks are not.
- **District-wise dashboard**: aggregate compliance % by District.
- **Engineer-wise dashboard**: visit count / compliance by Employee.
- **POP-wise visit history**: chronological list of `PMVisit` per POP.
- **Monthly MIS / Excel export**: tabular export of the above aggregates.

## Open Decisions (to confirm before further backend implementation)

1. UUID vs integer primary keys — **resolved for the implemented tables**
   (District/Block/GP/POP/Employee all use integer PKs); still open for
   `PMVisit`/`PMPhoto`.
2. Whether `district_id`/`block_id` are denormalized onto `POP` —
   **resolved: no**, resolved via joins (see POP section above). Still
   open for `PMVisit`.
3. Exact enum values for `sync_status` — **resolved**: `VisitSyncStatus`
   (`localOnly`/`pendingSync`/`syncing`/`synced`/`syncFailed`), see
   "Offline Storage & Synchronization". Per-photo `upload_status`
   remains open — it's still always `pending` today; nothing sets it
   to `uploaded`/`failed` per-photo yet, only the visit-level status
   reflects a sync attempt's outcome. (`role` was dropped — see
   Employee section above.)
4. Definition of a "fortnight period" (calendar-based 1–15/16–end, or
   rolling 14-day windows from first visit).
5. **When official POP latitude/longitude data arrives**: how it's
   imported/validated, and the exact geofence radius policy (fixed
   default vs per-POP).
6. How a device-generated `pm_visits.id` (see #8) reconciles with a
   future backend `PMVisit.id` once sync/submission is implemented
   (e.g. client-generated UUID accepted as-is vs. server-assigned ID
   returned on first sync).
