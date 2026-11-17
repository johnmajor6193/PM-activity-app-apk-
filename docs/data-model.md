# Data Model — TANFINET POP PM Monitoring System

This document defines the core entities and relationships the backend
(PostgreSQL, via FastAPI) will store. It is a planning reference for the
next development phase — no tables or ORM models are created yet.

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

## 1. District

| Field | Type | Notes |
|---|---|---|
| id | UUID / int, PK | |
| name | string | unique |
| code | string | optional short code |

## 2. Block

| Field | Type | Notes |
|---|---|---|
| id | UUID / int, PK | |
| district_id | FK → District | |
| name | string | |
| code | string | optional |

## 3. GP (Gram Panchayat)

| Field | Type | Notes |
|---|---|---|
| id | UUID / int, PK | |
| block_id | FK → Block | |
| name | string | |

## 4. POP (Point of Presence)

| Field | Type | Notes |
|---|---|---|
| id | UUID / int, PK | |
| gp_id | FK → GP | |
| name / pop_code | string | unique identifier used in the field |
| latitude | decimal | POP's registered geofence center |
| longitude | decimal | POP's registered geofence center |
| geofence_radius_m | int | allowed deviation radius in meters for geofence validation |

`district_id` / `block_id` are derivable via GP/POP's parent chain but may
be denormalized onto POP for simpler queries (decision deferred to backend
implementation step).

## 5. Employee

| Field | Type | Notes |
|---|---|---|
| id | UUID / int, PK | |
| employee_code | string | unique, used for login |
| name | string | |
| phone | string | |
| password_hash | string | |
| role | enum | e.g. `field_engineer`, `admin` (roles finalized later) |
| assigned_district_id | FK → District, nullable | optional scoping |
| is_active | bool | |

## 6. PMVisit

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
| within_geofence | bool | computed against POP geofence_radius_m |
| sync_status | enum | `pending_sync`, `synced`, `sync_failed` |
| fortnight_period | string / date range | which fortnight this visit satisfies, for compliance tracking |

## 7. PMPhoto

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

## Compliance / Reporting (derived, not stored directly)

These are computed from the above, to support the dashboards and MIS
export planned for a later phase:

- **Fortnightly compliance**: for each POP, was a valid `PMVisit` (5/5
  photos, within geofence) submitted in each fortnight period?
- **District-wise dashboard**: aggregate compliance % by District.
- **Engineer-wise dashboard**: visit count / compliance by Employee.
- **POP-wise visit history**: chronological list of `PMVisit` per POP.
- **Monthly MIS / Excel export**: tabular export of the above aggregates.

## Open Decisions (to confirm before backend implementation)

1. UUID vs integer primary keys.
2. Whether `district_id`/`block_id` are denormalized onto `POP` and
   `PMVisit` for query simplicity.
3. Exact enum values for `role`, `sync_status`, `upload_status`.
4. Definition of a "fortnight period" (calendar-based 1–15/16–end, or
   rolling 14-day windows from first visit).
