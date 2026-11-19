# Data Model — TANFINET POP PM Monitoring System

This document defines the core entities and relationships the backend
(PostgreSQL, via FastAPI) stores. Employee, District, Block, GP, and POP
are fully implemented. PMVisit and PMPhoto exist backend-side only in
the minimal form the District/Engineer/POP-wise dashboard needs (see
"Backend PmVisit / PmPhoto" below) — the mobile app's own on-device
tables (see "PM Visit & PM Photo — Local (On-Device) Implementation")
remain the source of truth for capture, offline storage, and the
submission lifecycle itself.

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
an incomplete (`draft` or `inProgress`) visit for the same POP via
`PmVisitRepository.getResumableVisit` and continues it, rather than
starting a duplicate.

**`pm_visits.status` — `VisitSyncStatus`** (implementation:
`mobile_app/lib/features/pm_visit/domain/entities/visit_sync_status.dart`).
This is the visit's full lifecycle, from first capture through a
confirmed Google Drive upload — see "PM Visit Submission and
Validation" below for how `readyForSubmission` onward is driven:

| Value | Meaning |
|---|---|
| `draft` | Visit started; no photo confirmed yet. |
| `inProgress` | At least one, but not all 5, mandatory photos confirmed. |
| `readyForSubmission` | All 5 mandatory photos confirmed and valid. Set automatically, offline, the moment the 5th is confirmed — no button press, no network call. The engineer may now open Review & Submit. |
| `pendingSync` | The engineer tapped Submit (or Retry); queued for upload. Also the state a visit is left in if Submit was tapped with no internet connection. |
| `syncing` | A sync attempt is in progress right now. |
| `synced` | Upload to Google Drive succeeded. Transient — `PmVisitController.submitVisit` immediately advances it to `submitted`. |
| `submitted` | Terminal success state. The visit is fully synced and complete; submitting again is a no-op (duplicate-submission guard). |
| `syncFailed` | The most recent sync attempt failed. The visit and its photos are **never** deleted for this; it stays eligible for retry via Submit/Retry. |

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

### PM Visit Submission and Validation

Implementation: `mobile_app/lib/features/pm_visit/presentation/pm_visit_controller.dart`
(`submitVisit`) and `pm_visit_submission_screen.dart` (the Review &
Submit screen). This module adds the engineer-facing submission step
and its validation gate on top of the existing capture/offline-storage/
sync foundation above — it does not change `SyncManager`, the Google
Drive pipeline, or the capture flow.

**Validation gate.** `submitVisit()` refuses to run unless
`PmVisitController.allPhotosValidForSubmission` is true: every one of
the 5 mandatory categories has a confirmed photo, and that photo is
itself valid per `PmPhotoRecordValidation.isValidForSubmission`
(non-empty original path, non-empty watermarked path, and a plausible
GPS fix — see `GpsReadingValidation.isPlausible`). This is a basic
sanity check on the GPS values themselves (not NaN, latitude in
[-90, 90], longitude in [-180, 180], non-negative accuracy) — **it is
not geofence validation and never compares against a POP coordinate**,
since no POP latitude/longitude master data exists (see "POP
Geo-Coordinates — Deferred" above). In normal operation every confirmed
photo already satisfies this; the check mainly guards against
corrupted or legacy rows.

**Submission screen contents** (`PmVisitSubmissionScreen`): Employee
ID/name, District, Block, GP, POP ID, visit date/time, a checklist of
all 5 mandatory categories (✓/✗ per category, with a thumbnail of the
watermarked evidence photo, tappable for a full preview), and the
current `VisitSyncStatus`. The Submit (or Retry, when `syncFailed`)
button is enabled only when `PmVisitController.canSubmit` is true.

**Duplicate-submission protection and idempotency.** `submitVisit()`
sets `isSyncing = true` synchronously, before its first `await`, and
returns immediately if already `isSyncing` or if the visit's status
isn't `readyForSubmission`/`syncFailed` — so a rapid double-tap, or
calling Submit again after `submitted`, never issues a second upload.
Retrying after a failure is safe because `SyncManager` never deletes or
modifies local data on a failed or skipped attempt; a retry simply
repeats the same sync call.

**Offline submission.** Tapping Submit with no connection moves the
visit to `pendingSync` (so it is queued) and `SyncManager.syncVisit`
then reports `skippedNoConnection`, leaving the status at `pendingSync`
with a message explaining why — nothing is lost, and the next Submit/
Retry (or a background `trySyncPendingVisits` call) picks it up.

**What is explicitly not implemented here**: geofence validation,
dashboards, MIS reports, analytics, new authentication, and new photo
categories — all out of scope for this module.

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

**Expected state flow** (`VisitSyncStatus` — unchanged `SyncManager`
mechanics; see "PM Visit Submission and Validation" above for how a
visit reaches `PENDING_SYNC` and for the `SYNCED` → `SUBMITTED` step):

```
PENDING_SYNC → SYNCING → SYNCED → SUBMITTED   (upload succeeds)
PENDING_SYNC → SYNCING → SYNC_FAILED          (upload fails; retry later, nothing local is touched)
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

## Backend PmVisit / PmPhoto (dashboard data source)

Implementation: `backend/app/models/pm_visit.py`,
`backend/app/models/pm_photo.py`, written by
`backend/app/services/pm_visits.py:record_synced_visit`, called from
`POST /visits/{visit_id}/sync` (`backend/app/api/v1/endpoints/visits.py`)
**only after** `drive_service.upload_visit_photos` has already
succeeded for every photo — never before, and never on a failed or
skipped sync.

This is a deliberately minimal backend-side record of "this visit's
photos are confirmed on Google Drive" — it exists to give the
District/Engineer/POP-wise dashboard (below) something to read, not to
duplicate the mobile app's own on-device `pm_visits`/`pm_photos`
tables (see "PM Visit & PM Photo — Local (On-Device) Implementation"
above), which remain the source of truth for in-progress capture,
offline storage, and the submission lifecycle. Resolves Open Decision
#6 below: the client-generated visit id is accepted as-is as the
backend `PmVisit.id`, no separate server-assigned id.

**`pm_visits`**:

| Column | Type | Notes |
|---|---|---|
| id | TEXT, PK | the same client-generated visit id used in the Drive folder path and the on-device database — not a separate backend-assigned id |
| employee_id | FK → Employee | the **verified JWT identity** (`current_employee.id`), never `visit_metadata.employee_id` from the request body |
| pop_id | FK → POP | |
| visit_date | TEXT (YYYY-MM-DD) | the app-sent visit date; what fortnight compliance buckets by |
| first_synced_at, last_synced_at | timestamp | when this backend first recorded the visit, and when it was last (re-)synced |

`district_name`/`block_name`/`gp_name`/`pop_code` are **not** stored
here — resolved by joining through `pop_id` → POP → GP → Block →
District at query time (same pattern as `locations.py:get_pop`), so a
dashboard query can never reflect a stale hierarchy name independently
of what `/locations` reports today. There is also no `within_geofence`
column and no visit-level check-in GPS — neither exists anywhere in
this system (see "POP Geo-Coordinates — Deferred" above); only
per-photo GPS (`pm_photos` below) is ever captured.

**`pm_photos`** (composite PK `(visit_id, category)`, mirroring the
on-device table's own PK): `captured_at`, `gps_lat`/`gps_lng`/
`gps_accuracy_m`, `drive_file_id`, `drive_file_link` — exactly the
metadata already available from the sync request and the Drive
upload result; no image bytes or local file path (those stay
on-device only).

**Re-syncing the same visit_id upserts, not duplicates**: its `pm_visits`
row is updated in place and its `pm_photos` rows are replaced, mirroring
the Drive-level idempotency (`duplicate: true`) that already existed.
A failed `record_synced_visit` call (e.g. a bad `pop_id`) is reported
to the app as a clean `"failed"` sync response, the same shape as a
Drive failure — even though the photos are already on Drive at that
point; nothing here can mark local evidence for deletion either way.

## District / Engineer / POP-wise Dashboard

Implementation: `backend/app/services/compliance.py`,
`backend/app/api/v1/endpoints/dashboard.py`. All three endpoints
require a logged-in employee (`get_current_employee`, same as
`/locations/*`) and read only the `PmVisit`/`PmPhoto` rows above.

**A mobile (Flutter) Dashboard UI now consumes these endpoints** — see
"Dashboard UI (mobile)" below. A separate **web admin dashboard**
remains a later phase per the top-level README; this backend module
is also the data API that will eventually serve it, unchanged.

- **`GET /api/v1/dashboard/districts?date=YYYY-MM-DD`** — for each
  District, its active POPs broken down individually (see "Completed
  vs pending" below), plus the resulting aggregate counts and
  compliance % for the fortnight containing `date` (defaults to today).
- **`GET /api/v1/dashboard/engineers?date=YYYY-MM-DD`** — for each
  active Employee, how many visits they synced in that fortnight, and
  how many were fully compliant. Every active employee is listed,
  including zero-visit ones.
- **`GET /api/v1/dashboard/pops/{pop_id}/visits`** — every synced visit
  for one POP, most recent first, each with its full category
  breakdown (see "Photo/category breakdown" below). Not windowed to a
  fortnight.

**"Fully compliant" means all 5 mandatory categories were actually
persisted for that visit** (`PmPhoto.category` covers
`MANDATORY_PHOTO_CATEGORIES`, `app/models/pm_photo.py`) — computed from
what was actually synced, not merely that a sync happened. The sync
endpoint itself does not enforce category completeness (that
validation lives in the mobile app, `PmVisitController.
allPhotosValidForSubmission`); this is **not** geofence validation and
never involves a POP coordinate, consistent with every other module.

### Completed vs pending (per-POP, per fortnight)

Each district's response includes a `pops` list (`PopPeriodStatusOut`,
`backend/app/schemas/dashboard.py`), one entry per active POP, each
with a `status` of `"completed"` or `"pending"`:

- **`"completed"`** — this POP has *at least one* successfully synced
  `PmVisit` in the queried fortnight. This is the **only** positive
  signal the backend can produce — "a visit was persisted" — per the
  principle that only states the existing data actually supports are
  exposed, nothing invented.
- **`"pending"`** — this POP has **no** synced visit at all in the
  period. The district-level `completed_pops`/`pending_pops` counts
  (new, alongside the existing `compliant_pops`/`compliance_percent`,
  which still mean 5/5 categories specifically) are the aggregate of
  this same per-POP flag.

**Documented limitation, not solved here**: `"pending"` means only
"no synced visit yet" — it cannot distinguish an engineer currently
capturing this POP, one who hasn't started it at all, or one whose
sync failed and is waiting to retry. The mobile app's own
`draft`/`inProgress`/`readyForSubmission`/`pendingSync`/`syncFailed`
states (see "Offline Storage & Synchronization" and "PM Visit
Submission and Validation" above) are **never transmitted to the
backend** — only a *successful* sync ever reaches it at all. Telling
these apart on the dashboard would require the mobile app to
additionally report a visit-start (or sync-attempt) event to the
backend, which does not exist today; this is a real dependency on
future mobile-side work, not a gap papered over with fake data here.

An engineer-level "pending POPs" equivalent is **not** provided: there
is no POP-to-employee assignment model in this system (`Employee.
assigned_district_name` is a plain string, not a roster of POPs), so
"POPs pending for this engineer" cannot be computed without inventing
one — out of scope here.

### Photo/category breakdown

Both the per-POP entries above and every entry in `GET
/dashboard/pops/{pop_id}/visits` (`PopVisitOut`) now include
`categories_present`/`categories_missing` — the exact mandatory
categories (sorted) found or not found among that visit's `PmPhoto`
rows (`app/services/compliance.py:category_breakdown`). A `"pending"`
POP has `categories_present: []` and all 5 in `categories_missing`,
since there is no visit to check. This sits alongside, not in place
of, `is_compliant` (which stays exactly "all 5 present").

**Fortnight definition — resolves Open Decision #4 below**: calendar
fortnights, the 1st–15th and the 16th–end-of-month, chosen over a
rolling 14-day window because it needs no "since when" reference point
or per-POP/per-employee state to track. `fortnight_bounds()` in
`compliance.py` is the single place this is computed; revisit there if
a rolling window turns out to be what's actually needed.

**Known scale limitation**: compliance aggregation queries every
`PmVisit` row and filters/groups in Python rather than in SQL. This is
correct and simple at this project's current scale (one row per
successfully synced visit, no production data yet) but would need
revisiting — an indexed/SQL-side date filter — before a large volume
of visits makes an in-Python scan too slow.

**Monthly MIS / Excel export is implemented** — see "Monthly MIS /
Excel Export" below.

## Monthly MIS / Excel Export

Implementation: `backend/app/services/mis_export.py`,
`backend/app/api/v1/endpoints/mis.py`. Protected the same way as
`/dashboard/*` (`get_current_employee`). Reads only the same
`PmVisit`/`PmPhoto` data the Dashboard already reads and reuses its
`is_compliant`/`category_breakdown` helpers unchanged — this is a
different *shape* of the same data (a flat, downloadable file instead
of a JSON summary), not a new data source or a new compliance rule.

**`GET /api/v1/mis/export?year=YYYY&month=MM`** — one row per
successfully synced PM visit in that calendar month, plus one
`Pending` row for every *active* POP (within any geographic filter
given) that received none that month — the same completed/pending
concept the Dashboard already uses (see "Completed vs pending"
above), just at monthly instead of fortnightly grain. A POP visited
twice in the month gets two rows: this is a ledger of real events, not
a POP-level summary, so nothing is deduplicated or averaged away.

**Columns** (`app/services/mis_export.py:COLUMNS`, in this exact
order): Visit ID, Visit Date, Employee ID, Employee Name, District,
Block, GP, POP Code, POP Name, Visit Status (`Completed`/`Pending`),
Categories Present, Categories Missing, Overall Compliance
(`Compliant`/`Incomplete`, blank for `Pending` rows), Sync Status
(`Synced`/`Not Synced`), First Synced At, Last Synced At. Every
column is read directly from `PmVisit`/`PmPhoto`/`Employee`/`Pop`/
`GramaPanchayat`/`Block`/`District`, or derived the same way the
Dashboard already derives it — nothing is invented, and `Visit ID` was
added beyond the originally-requested column list only because it is
real, already-persisted data useful for tracing a row back to its
Google Drive folder (which is named after the same id).

**Known limitation — "Sync Status" currently always mirrors "Visit
Status"** (`Synced` ⟺ `Completed`, `Not Synced` ⟺ `Pending`): a
`PmVisit` row is only ever written *after* its Drive upload has
already succeeded (see "Backend PmVisit / PmPhoto" above), so the
backend has no visible intermediate, failed, or offline sync state to
report as a genuinely independent value — those exist only on the
mobile device and are never transmitted. The column is still included
because it was explicitly requested, not because today's data
supports a richer answer than Visit Status already gives.

**Not included, because it wasn't in the requested column list and
would need deciding how to flatten multiple values per row**: the
per-photo Google Drive file links (`PmPhoto.drive_file_id`/
`drive_file_link`) exist in the data model and could be added later
(e.g. one combined column, or one per category) if O&M management
wants direct links to the evidence photos from the report itself.

**Filtering**: `district_id`, `block_id`, `gp_id`, `pop_id` (any
combination, matching the existing District→Block→GP→POP hierarchy
exactly) and `employee_id` (the employee's `employee_code`, e.g.
`ENG001`). Setting `employee_id` suppresses `Pending` rows entirely:
"employee X didn't visit POP Y" is not the same claim as "POP Y was
not visited by anyone," so an employee-scoped export reports only
that employee's actual visits. An unmatched filter combination (an
unknown id, or an employee with no visits that month) returns a
report with only the header row — not a 404 — since several
independent optional filters can combine, and "nothing matched" is a
normal result, not an error.

**Format**: `format=csv` (default) or `format=xlsx`
(`openpyxl`, now a real dependency — see `backend/requirements.txt`).
Both are built from the exact same row data; only the serialization
differs. The response sets `Content-Disposition: attachment` with a
`mis_export_<year>-<month>.<ext>` filename, so it downloads as a real
file in a browser or any HTTP client — this is what makes it "usable
as an Excel/CSV-style MIS report," not just another JSON endpoint.

**"Monthly" vs the Dashboard's "fortnightly"**: these are two
different, both previously documented granularities for two different
purposes — fortnightly *compliance* checking (has this POP been
visited this fortnight) vs. monthly *management* reporting (every
visit and every gap across the whole month, which spans two
fortnights) — not a new or conflicting period rule.
`app/services/mis_export.py:month_bounds` is the one place "a month"
is defined for this module, parallel to `compliance.py:fortnight_bounds`.

**Mobile UI**: a "Download MIS Report" button now consumes this
endpoint — see "MIS Report Download (mobile)" below. No web admin page
consumes it yet.

## Dashboard UI (mobile)

Implementation: `mobile_app/lib/features/dashboard/` (`domain`/`data`/
`presentation`, same layering as every other feature). Reads only the
backend endpoints above — no mock/placeholder data anywhere, and no
new business rule: fortnight boundaries, compliance percentages, and
completed/pending status are all computed server-side and simply
displayed.

- **`DashboardScreen`** — two tabs, **Districts** and **Engineers**,
  both for the same selected fortnight. A header lets the engineer
  step to the previous/next fortnight or jump back to today; "previous"
  /"next" reuse the `period_start`/`period_end` the backend already
  returned (`start - 1 day` / `end + 1 day`) rather than re-deriving
  fortnight math in Dart — `fortnight_bounds` stays the single place
  that logic lives.
  - **Districts tab**: an overall summary (aggregated client-side from
    the per-district numbers already returned — no new data), then one
    expandable card per District with its compliance % and a per-POP
    list showing each POP's completed/pending status and, when
    incomplete, exactly which mandatory categories are missing (by
    name, reusing the mobile app's own `PhotoCategory.label` mapping —
    not a second category-name definition).
  - **Engineers tab**: one row per active Employee with visits synced
    and a compliant-visits ratio.
- **`PopVisitHistoryScreen`** (opened by tapping a POP, from either the
  Districts tab or POP Selection's new "View Visit History" button) —
  the POP's District › Block › GP context, fetched from the existing,
  unchanged `GET /locations/pops/{id}` endpoint (not a dashboard
  endpoint; this is why POP-level District/Block/GP context needed no
  backend change), plus every synced visit for that POP via
  `GET /dashboard/pops/{id}/visits`, each with its own compliance
  badge and full category present/missing breakdown.
- **Entry points** (both purely additive, no existing screen logic
  changed): `ProfileScreen` gained a "View Dashboard" button;
  `PopSelectionScreen`'s POP detail card gained a "View Visit History"
  button alongside the existing "Start PM Visit" one.
- **Auth reused as-is**: every dashboard request goes through
  `DashboardApiClient`, which attaches `Authorization: Bearer <token>`
  from the same `AuthSession` every other protected call already uses
  (see "Protected endpoints (JWT verification)" in `backend/README.md`)
  — no new login flow, no new token storage.

**UI verification**: see `mobile_app/README.md` ("Dashboard UI
verification") for the full writeup — no Android device/emulator
exists in this environment, so that pass has not been done; 14
`testWidgets` tests render the real widget trees instead (at a
360×800 "normal mobile screen" test width) as the strongest check
available without one, and caught/fixed one real overflow bug in
`_OverallSummaryCard`'s header row.

**Known limitation — sync-timestamp display precision**: on SQLite
(dev/test), `PmVisit.first_synced_at`/`last_synced_at` round-trip
through storage as naive timestamps (no `+00:00` offset), because
SQLite has no native timezone-aware datetime type, even though the
column is declared `DateTime(timezone=True)` and written with
`datetime.now(timezone.utc)`. The Flutter side therefore parses them
with `DateTime.parse` and treats the result as local rather than UTC
when no offset is present; the on-screen "Synced:" time can be off by
the server's UTC offset in this dev/test setup. On Postgres the column
preserves the offset and this does not occur. Not fixed here — it is
a pre-existing backend/storage nuance, not something the dashboard UI
work introduced, and correcting it means changing already-implemented/
verified backend code, out of scope for a UI-only module.

## Pre-device-testing review (bug fix)

Before the first real Android device/emulator pass, the full backend
and mobile implementation was reviewed specifically for defects that
only a real device's timing/latency would expose (not style or
hypothetical future issues). The backend had none. The mobile app had
two genuine, fixed bugs:

**Dispose-after-use crash in every `ChangeNotifier` controller**
(`AuthController`, `DashboardController`, `MisReportController`,
`PopVisitHistoryController`, `PopSelectionController`,
`PmVisitController`). None of them guarded against the screen being
popped (e.g. the engineer backs out) while an `await` was still in
flight — a real device's GPS fix, camera capture, or network round
trip can easily take long enough for this to happen, whereas
`flutter test`'s synchronous fakes never exercise the window. The
pending call's later `notifyListeners()` then threw
`"A <Controller> was used after being disposed"`, crashing the
screen transition. **Fixed** identically in all six controllers: each
tracks `bool _disposed` (set in an overridden `dispose()`) and
overrides `notifyListeners()` to no-op once disposed — the async work
itself still runs to completion (so a photo capture or submission
still persists correctly even if the screen was already left), only
the now-pointless UI notification is skipped. Proven with a new
regression test
(`pm_visit_controller_test.dart`, "disposing the controller while
capturePhoto is awaiting GPS does not throw") — confirmed to fail with
the old `Bad state: A PmVisitController was used after being disposed`
error before the fix, and pass after it.

**The release app could not reach the backend at all.**
`android/app/src/main/AndroidManifest.xml` declared no
`android.permission.INTERNET` — only the debug/profile build
variants' own manifests had it (added there only for the Flutter
tool's dev-time use, e.g. hot reload), and none of the app's plugins
(`http`, `connectivity_plus`, `geolocator`, `image_picker`, `sqflite`)
declare it either. A release build (`flutter build apk`, the normal
way to produce an installable APK) therefore had **zero** network
permission. Separately, nothing declared
`android:usesCleartextTraffic="true"`, and the backend is plain
`http://` by design in this dev/LAN setup (`ApiConfig.baseUrl`) —
Android 9+ blocks cleartext HTTP by default, so even a debug build
(which already had `INTERNET` via its own manifest) would still have
been unable to reach the backend. **Fixed** by declaring both in the
main manifest, so every build type can reach the `http://` backend.
Not independently verified by actually running `flutter build apk`
in this environment (no Android SDK here) — only the manifest's XML
validity and the standard, well-documented nature of this exact fix
were confirmed; the first real build on a machine with the Android
SDK is this fix's first true verification.

**One risk identified but deliberately left unfixed, pending real-device
evidence**: `WatermarkService.applyWatermark` (`watermark_service.dart`)
decodes the captured JPEG with `image`'s `decodeImage`, which does
**not** auto-apply the file's EXIF orientation tag, and never calls
`img.bakeOrientation()`. Synthetic test images carry no EXIF
orientation, so this can't be caught by `flutter test`. Many real
Android camera stacks save a portrait photo as a landscape pixel
buffer plus an EXIF `Orientation` tag rather than pre-rotated pixels;
if that happens here, the watermark banner — drawn at the bottom of
the *raw*, undecoded-orientation buffer — could end up on the wrong
edge once an EXIF-aware viewer (including the app's own Retake/Confirm
review screen) displays the image rotated. This is a real-device-only
risk, not a confirmed bug (it may not reproduce on every device/camera
combination), so it was not speculatively patched; it is called out
explicitly as its own item in the device testing checklist
(`docs/device-testing-checklist.md`) instead, with a note to patch via
`img.bakeOrientation()` if and only if it's actually observed.

## MIS Report Download (mobile)

Implementation: `mobile_app/lib/features/dashboard/` (same feature
folder as the Dashboard, since the button lives on `DashboardScreen`
and both read backend reporting data; no new top-level feature was
created for one button).

- **`MisExportApiClient`** (`data/`) — calls
  `GET /api/v1/mis/export?year=&month=&format=xlsx` and returns the
  raw response bytes on success. Kept separate from
  `DashboardApiClient` because that client's shared `_get()` helper
  always `jsonDecode`s the response body, which doesn't work for this
  endpoint's binary `.xlsx` payload — rather than change `_get()`'s
  behavior for every other caller, a second, small client was added.
  Auth is identical: the same `AuthSession`-held JWT is attached as
  `Authorization: Bearer <token>`, exactly as `DashboardApiClient`
  already does.
- **`MisReportDownloadService`** (`data/`) — calls
  `MisExportApiClient.downloadXlsx`, then writes the bytes to
  `<app documents dir>/mis_reports/mis_export_<year>-<month>.xlsx`
  using `path_provider` + `dart:io`, the same on-device storage
  pattern `camera_capture_service.dart` already uses for PM visit
  photos — no new dependency, no new Android storage permission.
  Returns the saved file's path.
- **`MisReportController`** (`presentation/`) — a small
  `ChangeNotifier` with an `idle`/`downloading`/`success`/`error`
  status, mirroring `DashboardLoadStatus`'s shape. Holds
  `savedFilePath` on success and `errorMessage` on failure.
- **`DashboardScreen`** — gained one AppBar action ("Download MIS
  Report"): a download icon that swaps for a small spinner and
  disables itself while a download is in flight, and reports the
  result via `SnackBar` — the saved file path on success, or a clear
  message (reusing `DashboardFailure`'s messages, e.g. "Could not
  reach the server. Check your connection and try again.") on
  failure. The report always covers the device's current year/month;
  no month picker was added since the task asked for the smallest
  clean integration, not a new filter UI. `DashboardScreen` gained an
  optional `misReportController` constructor parameter, the same
  test-injection seam already used for its `controller` parameter.
- **Not touched**: GPS/photo capture, the watermark, offline SQLite
  storage, PM Visit submission, Google Drive sync, and the existing
  Districts/Engineers tabs and their controller — this module only
  adds new files plus one new AppBar action and controller field on
  `DashboardScreen`.
- **Verification**: `test/features/dashboard/mis_export_api_client_test.dart`
  (request path/query/headers, success/error handling, against a fake
  HTTP transport), `mis_report_download_service_test.dart` (real
  `dart:io` file write against a real temp directory, via a fake
  `PathProviderPlatform` — see `mobile_app/README.md` for why), and
  `mis_report_controller_test.dart` (status transitions) — plus 3 new
  `testWidgets` tests appended to `dashboard_screen_test.dart`
  covering the button's idle/loading/success/error states and that it
  disables itself mid-download. No Android device/emulator exists in
  this environment (see "Dashboard UI verification" in
  `mobile_app/README.md`), so confirming how the saved file actually
  surfaces to the end user on a real device (file manager visibility,
  or whether a "share"/"open" action is wanted to reach the
  user-facing Downloads folder) remains unverified here.

## Open Decisions (to confirm before further backend implementation)

1. UUID vs integer primary keys — **resolved**: District/Block/GP/POP/
   Employee all use integer PKs; the backend `PmVisit.id` uses the
   client-generated string id as-is instead (see "Backend PmVisit /
   PmPhoto" above) — a deliberate exception, not an oversight.
2. Whether `district_id`/`block_id` are denormalized onto `POP` —
   **resolved: no**, resolved via joins (see POP section above). The
   same resolution now also applies to the backend `PmVisit` table —
   see "Backend PmVisit / PmPhoto" above.
3. Exact enum values for `sync_status` — **resolved**: `VisitSyncStatus`
   (`draft`/`inProgress`/`readyForSubmission`/`pendingSync`/`syncing`/
   `synced`/`submitted`/`syncFailed`), see "Offline Storage &
   Synchronization" and "PM Visit Submission and Validation". Per-photo
   `upload_status`
   remains open — it's still always `pending` today; nothing sets it
   to `uploaded`/`failed` per-photo yet, only the visit-level status
   reflects a sync attempt's outcome. (`role` was dropped — see
   Employee section above.)
4. Definition of a "fortnight period" — **resolved**: calendar-based
   1st–15th / 16th–end-of-month — see "District / Engineer / POP-wise
   Dashboard" above.
5. **When official POP latitude/longitude data arrives**: how it's
   imported/validated, and the exact geofence radius policy (fixed
   default vs per-POP).
6. How a device-generated `pm_visits.id` reconciles with the backend
   `PmVisit.id` — **resolved**: accepted as-is, no separate
   server-assigned id — see "Backend PmVisit / PmPhoto" above.
