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
| drive_folder_path | string | e.g. `TANFINET_POP_PM_VISIT/<District>/<Block>` |
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
| pop_id | INTEGER | the backend `POP.id` this visit is for |
| pop_code | TEXT | denormalized for display without a join |
| started_at | TEXT (ISO 8601) | device-local timestamp |

**`pm_photos`** (one row per *confirmed* mandatory photo; retake
replaces the row for the same `(visit_id, category)`):

| Column | Type | Notes |
|---|---|---|
| visit_id, category | TEXT, TEXT — composite PK | `category` is one of `pop_rack`, `ups_battery`, `busbar`, `earth_pit_chamber`, `earth_pit_open_with_rod` |
| pop_id | INTEGER | |
| local_file_path | TEXT | device filesystem path; this is the only copy of the photo right now |
| captured_at | TEXT (ISO 8601) | the moment the camera took the photo |
| gps_latitude, gps_longitude, gps_accuracy_m | REAL | a **fresh GPS fix taken for this specific photo**, not reused from visit start or any other photo. Not compared against any POP coordinate — no geofence check is performed anywhere in this module (see "POP Geo-Coordinates — Deferred" above) |
| upload_status | TEXT | `pending` / `uploaded` / `failed` — prepares for sync, but nothing sets it to anything but `pending` yet |
| watermarked_file_path | TEXT, nullable | reserved for the GPS-watermark step; always `NULL` today |
| drive_file_id, drive_file_link | TEXT, nullable | reserved for Google Drive upload; always `NULL` today |

What this deliberately does **not** do yet: burn the watermark into the
image, upload anywhere, run a geofence check, or submit the visit. Those
are later modules; this schema is shaped so adding them means filling in
existing nullable columns / adding sync logic, not changing what is
captured today.

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
3. Exact enum values for `sync_status`, `upload_status` (`role` was
   dropped — see Employee section above).
4. Definition of a "fortnight period" (calendar-based 1–15/16–end, or
   rolling 14-day windows from first visit).
5. **When official POP latitude/longitude data arrives**: how it's
   imported/validated, and the exact geofence radius policy (fixed
   default vs per-POP).
6. How a device-generated `pm_visits.id` (see #8) reconciles with a
   future backend `PMVisit.id` once sync/submission is implemented
   (e.g. client-generated UUID accepted as-is vs. server-assigned ID
   returned on first sync).
