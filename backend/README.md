# backend — TANFINET POP PM Monitoring API (FastAPI)

REST API backend: employee auth, District/Block/GP/POP master data, PM
visit records (GPS, timestamps, photo metadata, Google Drive links), and
later, compliance dashboards and MIS export.

## Structure

```
app/
├── main.py              # FastAPI app instance, router wiring, lifespan (create tables + dev seed), /health
├── core/
│   ├── config.py        # settings (env vars / .env), incl. auth_mode, secret_key
│   └── security.py      # JWT create/decode
├── api/
│   ├── deps.py          # get_current_employee() - JWT verification dependency, see "Protected endpoints" below
│   └── v1/
│       ├── router.py        # aggregates all v1 routers
│       └── endpoints/
│           ├── auth.py        # POST /auth/login (implemented, public)
│           ├── locations.py   # District/Block/GP/POP hierarchy (implemented, protected)
│           ├── visits.py      # POST /visits/{id}/sync - Google Drive upload + PmVisit persistence (implemented, protected)
│           └── dashboard.py   # GET /dashboard/districts, /engineers, /pops/{id}/visits (implemented, protected)
├── models/
│   ├── employee.py          # Employee ORM model (implemented)
│   ├── district.py, block.py, grama_panchayat.py, pop.py  # location hierarchy (implemented)
│   └── pm_visit.py, pm_photo.py  # backend-side record of a successfully synced visit (implemented, minimal - see docs/data-model.md)
├── schemas/
│   ├── auth.py               # LoginRequest/LoginResponse/EmployeeProfile, with validation
│   ├── location.py           # DistrictOut/BlockOut/GpOut/PopSummary/PopDetail
│   ├── drive_sync.py         # VisitSyncMetadata/PhotoSyncMetadata/VisitSyncResponse
│   └── dashboard.py          # DistrictDashboardResponse/EngineerDashboardResponse/PopVisitOut
├── db/
│   ├── base.py            # declarative base
│   ├── session.py         # SQLAlchemy engine/session
│   ├── deps.py             # get_db() FastAPI dependency
│   └── seed_dev_data.py    # dev-mode seed: demo employees + a small location hierarchy
├── services/auth/           # authentication strategy (modular, see "Auth design" below)
│   ├── base.py               # AuthStrategy interface
│   ├── dev_login.py          # DevLoginStrategy: Employee ID + mobile number lookup
│   ├── errors.py             # AuthenticationError
│   └── __init__.py           # get_auth_strategy() factory, keyed on settings.auth_mode
├── services/drive/           # Google Drive upload (modular, see "Google Drive Upload" below)
│   ├── base.py                 # GoogleDriveUploadService interface, VisitMetadata/PhotoUploadItem/PhotoUploadResult
│   ├── naming.py                # build_drive_folder_segments / build_drive_filename (pure, unit-tested)
│   ├── google_drive_upload_service.py  # GoogleDriveServiceAccountUploadService: the real implementation
│   ├── not_configured_drive_upload_service.py  # NotConfiguredDriveUploadService: fails clearly, no credentials needed
│   ├── fake_drive_upload_service.py     # FakeDriveUploadService: in-memory, for tests
│   └── __init__.py               # get_drive_upload_service() factory, keyed on settings.google_service_account_file
├── services/pm_visits.py     # record_synced_visit() - persists a visit only after its Drive upload succeeds
└── services/compliance.py    # fortnight_bounds() + district/engineer/POP compliance aggregation, see "Dashboard" below
tests/
├── conftest.py            # points the app at an isolated SQLite file; `client`/`db_session`/`auth_headers`/`seeded_pop_id` fixtures
├── test_health.py
├── test_auth.py              # login success/failure/validation/inactive-account cases
├── test_auth_dependency.py   # get_current_employee JWT verification: valid/missing/malformed/expired/wrong-claims
├── test_locations.py         # hierarchy listing, active-only filtering, POP detail, 404s, anonymous rejection
├── test_drive_sync.py        # upload success/failure/retry/idempotency, folder path, file naming, auth, PmVisit persistence
└── test_dashboard.py         # fortnight_bounds unit tests + district/engineer/POP dashboard endpoints
```

## Status

**Employee Login is implemented.** `POST /api/v1/auth/login` accepts
`employee_id` + `mobile_number`, returns a JWT `access_token` plus the
employee's basic profile (`employee_id`, `name`, `assigned_district`).

**POP Selection (District → Block → GP → POP) is implemented.**
`GET /api/v1/locations/districts` → `.../districts/{id}/blocks` →
`.../blocks/{id}/gps` → `.../gps/{id}/pops` → `.../pops/{id}` walks the
hierarchy down to a single POP's basic details.

**POP has no latitude, longitude, or geofence radius, by design.** The
official POP coordinate master data has not been supplied, and none of
the code, seed data, or API responses use placeholder/fake coordinates.
POP geofence validation is deferred until that data exists — see
`app/models/pop.py` and `docs/data-model.md` ("POP Geo-Coordinates —
Deferred"). This does not affect per-photo GPS capture: the mobile app's
PM Visit module captures and watermarks live per-photo GPS entirely
on-device (no backend involvement) — see `docs/data-model.md`.

**`POST /api/v1/visits/{visit_id}/sync` is implemented.** This is the
Google Drive upload relay the Flutter app's PM Visit Submission step
calls: it accepts a visit's 5 watermarked photos plus metadata and
uploads them to Google Drive (or fails clearly if no service account
is configured) — see "Google Drive Upload" below. On success, it now
also persists a minimal `PmVisit`/`PmPhoto` record (see "Dashboard"
below and `docs/data-model.md`) — this is not a full visit record the
way the mobile app's own on-device tables are; it exists only to give
the dashboard something to read.

**District/Engineer/POP-wise Dashboard is implemented.**
`GET /api/v1/dashboard/districts`, `/engineers`, and
`/pops/{pop_id}/visits` read the `PmVisit`/`PmPhoto` rows above to
report fortnightly compliance — see "Dashboard" below. No web UI exists
for this yet (a later phase per the top-level README); these are the
data endpoints it will eventually call. Monthly MIS/Excel export is a
separate module, not built yet.

`Employee.assigned_district_name` remains a plain string (not a `District`
FK) — Employee Login was kept unchanged while building this module; see
the note in `app/models/employee.py` and `docs/data-model.md`.

### Auth design (dev login → OTP later)

The login endpoint depends only on `AuthStrategy`
(`app/services/auth/base.py`), not on how authentication actually works.
`DevLoginStrategy` (`app/services/auth/dev_login.py`) is the only
implementation right now: it looks up an employee by `employee_code` and
checks `mobile_number` matches — no OTP, no password. It's selected via
`settings.auth_mode` ("dev" by default) through `get_auth_strategy()`
(`app/services/auth/__init__.py`).

To add OTP later: implement a new `AuthStrategy` (e.g. `OtpStrategy`),
add an `"otp"` branch to `get_auth_strategy()`, and set
`AUTH_MODE=otp`. The endpoint and schemas do not need to change.

### Protected endpoints (JWT verification)

`POST /auth/login` issues a signed JWT (`app/core/security.py`), but
until now nothing actually verified one on any later request — every
other endpoint was reachable with no token at all. `app/api/deps.py`
adds `get_current_employee`, a FastAPI dependency that every protected
endpoint now depends on:

- **Protected** (require `Authorization: Bearer <token>`): every
  `/api/v1/locations/*` route (district/block/GP/POP lookups — wired at
  the router level, `app/api/v1/endpoints/locations.py`) and
  `POST /api/v1/visits/{visit_id}/sync` (`app/api/v1/endpoints/visits.py`).
- **Intentionally public**: `GET /health` (liveness check) and
  `POST /api/v1/auth/login` (this is how a token is obtained in the
  first place).
- The empty `dashboard` router has no routes yet, so there is nothing
  to protect there — add the dependency when it gets its first
  endpoint.

`get_current_employee` rejects with **401** (the request is never
processed) when the `Authorization` header is missing, isn't a Bearer
token, the JWT is malformed, its signature doesn't verify against
`settings.secret_key`, it has expired, or its `sub` claim doesn't match
an active `Employee` — all cases return the same generic
"Could not validate credentials." message (so a forged token can't be
debugged against the response), and nothing ever logs the token itself
or any claim value.

**`POST /visits/{visit_id}/sync` no longer trusts `employee_id` from
the request body.** The Google Drive metadata (`appProperties.employee_id`
on each uploaded file) always comes from `current_employee.employee_code`
— the verified JWT identity — even though the Flutter app still sends
its own `employee_id` in `visit_metadata` (unchanged wire format; that
field is simply no longer used for identity).

The JWT signing key (`settings.secret_key`) and verification logic stay
entirely server-side; nothing about this was added to or changed in
the Flutter app's own credentials. The mobile app now keeps the
`access_token` from a successful login in memory
(`mobile_app/lib/core/network/auth_session.dart`, never persisted to
disk or logged) and attaches it as `Authorization: Bearer <token>` on
every locations/sync request — see `mobile_app/README.md`. The login
UI and `/auth/login` request/response themselves are unchanged.

In `auth_mode == "dev"`, the app seeds two demo employees on startup if
the `employees` table is empty, and a small District → Block → GP → POP
hierarchy if the `districts` table is empty (`app/db/seed_dev_data.py`):

| Employee ID | Mobile Number | District |
|---|---|---|
| `ENG001` | `9876543210` | Chennai |
| `ENG002` | `9123456780` | Madurai |

| District | Block | GP | POP ID | Status |
|---|---|---|---|---|
| Chennai | Sholinganallur | Semmancheri GP | `POP-CHN-001` | Active |
| Chennai | Sholinganallur | Semmancheri GP | `POP-CHN-002` | **Inactive** (for testing the status filter) |
| Chennai | Sholinganallur | Kazhipattur GP | `POP-CHN-003` | Active |
| Chennai | Tambaram | Chitlapakkam GP | `POP-CHN-004` | Active |
| Madurai | Thiruparankundram | Avaniyapuram GP | `POP-MDU-001` | Active |

These are for local/dev/QA testing only — never enable `auth_mode=dev`
against a production database.

### Google Drive Upload

**The Flutter app never holds Google credentials.** It sends the 5
watermarked photos (never the plain originals) and visit/photo
metadata to this backend over HTTPS; only this server authenticates to
Google Drive and performs the actual upload. This is a deliberate
architecture decision, not an implementation detail — see
`mobile_app/lib/features/pm_visit/data/google_drive_upload_service.dart`
for the Flutter side of this same boundary.

**Endpoint:** `POST /api/v1/visits/{visit_id}/sync` — `multipart/form-data`:

| Field | Type | Contents |
|---|---|---|
| `visit_metadata` | form field, JSON string | `VisitSyncMetadata`: `visit_id`, `employee_id`, `pop_id`, `pop_code`, `district`, `block`, `gp`, `visit_date` (`YYYY-MM-DD`) |
| `photos_metadata` | form field, JSON array | One `PhotoSyncMetadata` per photo — `category`, `captured_at`, `latitude`, `longitude`, `accuracy_m` — matched to `files` **by position** (`photos_metadata[i]` ↔ `files[i]`) |
| `files` | file list | The 5 watermarked JPEGs, same order as `photos_metadata` |

Response (`VisitSyncResponse`, always HTTP 200 if the request itself
was well-formed — the Flutter app distinguishes success/failure by the
`status` field, not the HTTP status code):

```json
{
  "status": "synced",
  "photos": [
    {"category": "pop_rack", "drive_file_id": "...", "drive_file_link": "...", "duplicate": false}
  ],
  "message": null
}
```

`status: "failed"` (with a human-readable `message`) covers: malformed
metadata, a `visit_id` mismatch between the URL and the body, a
`photos_metadata`/`files` count mismatch, Drive not configured, or any
error Drive itself raised. In every one of these cases **no local data
is implicated at all** — the failure is reported back to the app, whose
`SyncManager` marks the visit `SYNC_FAILED` and leaves every local
photo and visit row untouched, exactly as before this module (see
`docs/data-model.md`, "Offline Storage & Synchronization").

**Folder structure** (created/found as needed, under
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
                            ├── POP-00125_POP-RACK_2026-11-17_172542.jpg
                            ├── POP-00125_UPS-BATTERY_2026-11-17_172601.jpg
                            └── ... (5 total)
```

**File naming** (`app/services/drive/naming.py:build_drive_filename`):
`<POP code>_<CATEGORY>_<YYYY-MM-DD>_<HHMMSS>.jpg` — e.g.
`POP-00125_POP-RACK_2026-11-17_172542.jpg`. The POP code is sanitized
(any character other than letters/digits/`-`/`_` becomes `-`) so the
name is always filesystem/Drive-safe.

**Idempotent, retry-safe uploads.** Both folder lookup and file lookup
check for an existing item with the same name under the same parent
before creating anything (`files.list` with a `name = '...' and
'<parent>' in parents` query). Retrying a sync for the same visit —
whether because the first attempt failed partway through, or just to
be safe — finds the already-uploaded folders/files and reuses them
(`duplicate: true` in the response) instead of creating duplicates.
Nothing here deletes an existing file, so a half-finished prior attempt
is always safe to retry on top of.

**Metadata on each file.** Visit ID, Employee ID, POP ID, District,
Block, GP, category, capture timestamp, latitude, longitude, and GPS
accuracy are attached to each uploaded file via Drive's
`appProperties` (visible via the Drive API, not just the folder path).

**Swappable implementations** (`app/services/drive/`, all behind the
`GoogleDriveUploadService` interface, selected by
`get_drive_upload_service()`):

| Implementation | When used | Behavior |
|---|---|---|
| `GoogleDriveServiceAccountUploadService` | `GOOGLE_SERVICE_ACCOUNT_FILE` is set | Real Drive v3 API calls |
| `NotConfiguredDriveUploadService` | no service account configured (the default) | Every call fails with a clear "not configured" message |
| `FakeDriveUploadService` | backend tests only (`app.dependency_overrides`) | In-memory, no network, tracks idempotency the same way the real service does |

### Google Drive Configuration (required from the company)

To enable real uploads, the company must provide a **Google Cloud
service account** with Drive API access:

1. In Google Cloud Console, create (or reuse) a project, enable the
   **Google Drive API**, and create a **service account**.
2. Create a JSON key for that service account and download it.
3. Service accounts have no personal Drive storage quota in most
   setups — grant it access to a **Shared Drive** (or a folder shared
   with its email address) where the `TANFINET PM Monitoring` folder
   tree should live.
4. Place the downloaded key file **outside of this repository** — e.g.
   at `backend/credentials/google-drive-service-account.json` (that
   path/directory is already in `.gitignore`), or wherever the
   deployment's secret storage mounts files.
5. Set these on the server (never commit them — see `.env.example`):

   ```bash
   GOOGLE_SERVICE_ACCOUNT_FILE=/path/to/google-drive-service-account.json
   GOOGLE_DRIVE_ROOT_FOLDER_NAME=TANFINET PM Monitoring   # optional, this is the default
   GOOGLE_DRIVE_PARENT_FOLDER_ID=<shared drive/folder id>  # optional, needed if using a Shared Drive
   ```

Until these are set, `/visits/{id}/sync` always responds
`status: "failed"` with a clear "Google Drive is not configured on
this server" message — it never silently pretends to succeed.

**Security notes:**
- The service-account key file is read from disk at runtime
  (`GOOGLE_SERVICE_ACCOUNT_FILE`); it is never hard-coded, never logged,
  and never sent to the Flutter app.
- `.gitignore` covers `backend/credentials/` (the whole directory) plus
  `**/service-account*.json` and `**/google-drive-credentials*.json`
  anywhere in the repo, so an accidentally-placed key file is very
  unlikely to be committed — but always double-check `git status`
  before committing if you've handled a real key file locally.
- `GOOGLE_DRIVE_ROOT_FOLDER_NAME`/`GOOGLE_DRIVE_PARENT_FOLDER_ID` are
  configuration, not secrets, and can be set however is convenient
  (`.env`, platform environment variables, deployment config).
- Swapping to a different Google authentication method later (e.g. a
  different service account, or workload identity federation) only
  means changing how `GoogleDriveServiceAccountUploadService.__init__`
  builds its `credentials` object — the interface, the endpoint, and
  every other implementation are unaffected.

### Dashboard (District / Engineer / POP-wise)

Three protected (JWT-required, same as `/locations/*`) read-only
endpoints, all under `/api/v1/dashboard`:

| Endpoint | Reports |
|---|---|
| `GET /districts?date=YYYY-MM-DD` | Per District: how many of its *active* POPs got at least one fully-compliant visit in the fortnight containing `date` (default: today), and the compliance %. |
| `GET /engineers?date=YYYY-MM-DD` | Per active Employee: visits synced and how many were fully compliant, in that same fortnight. Every active employee is listed, including zero-visit ones. |
| `GET /pops/{pop_id}/visits` | Every synced visit for one POP, most recent first — not windowed to a fortnight. 404 if the POP doesn't exist. |

**"Fully compliant"** means all 5 mandatory photo categories were
actually persisted for that visit (`app/models/pm_photo.py:
MANDATORY_PHOTO_CATEGORIES`) — not merely that a sync happened. This
is computed from what the backend actually recorded, never a geofence
check and never a POP coordinate.

**Fortnight = calendar fortnight** (1st–15th, 16th–end-of-month) —
`app/services/compliance.py:fortnight_bounds`. See `docs/data-model.md`
("District / Engineer / POP-wise Dashboard") for why this was chosen
over a rolling 14-day window, and for the exact `PmVisit`/`PmPhoto`
schema this reads.

**No web UI exists for this yet.** These are the data endpoints a
later admin-dashboard phase will call; nothing in this step adds a
page, a chart, or an Excel/MIS export.

**Known scale limitation**: both the district and engineer endpoints
load every `PmVisit` row and filter/aggregate in Python, not SQL. Fine
at this project's current scale; would need an indexed, SQL-side date
filter before a large production volume of visits makes that scan slow.

```bash
# after logging in and saving $TOKEN as shown further down:
curl -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8000/api/v1/dashboard/districts?date=2026-11-20"
curl -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8000/api/v1/dashboard/engineers?date=2026-11-20"
curl -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8000/api/v1/dashboard/pops/1/visits
```

## Running locally

Requires Python 3.11+ and a PostgreSQL instance (tables are created
automatically on startup; no Alembic migrations yet).

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # edit DATABASE_URL if needed

uvicorn app.main:app --reload
# then: curl http://127.0.0.1:8000/health
#
# /locations/* and /visits/{id}/sync now require a token (see
# "Protected endpoints (JWT verification)" above) - log in first:
#
#   TOKEN=$(curl -s -X POST http://127.0.0.1:8000/api/v1/auth/login \
#     -H "Content-Type: application/json" \
#     -d '{"employee_id": "ENG001", "mobile_number": "9876543210"}' \
#     | python3 -c 'import sys, json; print(json.load(sys.stdin)["access_token"])')
#
#   curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8000/api/v1/locations/districts
#
#   # Google Drive upload - "failed"/"not configured" unless GOOGLE_SERVICE_ACCOUNT_FILE is set:
#   curl -X POST http://127.0.0.1:8000/api/v1/visits/visit-1/sync \
#     -H "Authorization: Bearer $TOKEN" \
#     -F 'visit_metadata={"visit_id":"visit-1","employee_id":"ENG001","pop_id":7,"pop_code":"POP-00125","district":"Chennai","block":"Sholinganallur","gp":"Semmancheri GP","visit_date":"2026-11-17"}' \
#     -F 'photos_metadata=[{"category":"pop_rack","captured_at":"2026-11-17T17:25:42","latitude":11.1,"longitude":77.2,"accuracy_m":4.0}]' \
#     -F 'files=@/path/to/pop_rack_watermarked.jpg'
```

Run tests (uses an isolated SQLite file via `tests/conftest.py` — no
Postgres needed):

```bash
pip install pytest httpx
pytest
```
