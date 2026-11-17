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
├── api/v1/
│   ├── router.py        # aggregates all v1 routers
│   └── endpoints/
│       ├── auth.py        # POST /auth/login (implemented)
│       ├── locations.py   # District/Block/GP/POP hierarchy (implemented, no GPS fields)
│       └── visits.py, dashboard.py  # routers wired, no endpoints yet
├── models/
│   ├── employee.py          # Employee ORM model (implemented)
│   ├── district.py, block.py, grama_panchayat.py, pop.py  # location hierarchy (implemented)
├── schemas/
│   ├── auth.py               # LoginRequest/LoginResponse/EmployeeProfile, with validation
│   └── location.py           # DistrictOut/BlockOut/GpOut/PopSummary/PopDetail
├── db/
│   ├── base.py            # declarative base
│   ├── session.py         # SQLAlchemy engine/session
│   ├── deps.py             # get_db() FastAPI dependency
│   └── seed_dev_data.py    # dev-mode seed: demo employees + a small location hierarchy
└── services/auth/           # authentication strategy (modular, see "Auth design" below)
    ├── base.py               # AuthStrategy interface
    ├── dev_login.py          # DevLoginStrategy: Employee ID + mobile number lookup
    ├── errors.py             # AuthenticationError
    └── __init__.py           # get_auth_strategy() factory, keyed on settings.auth_mode
tests/
├── conftest.py            # points the app at an isolated SQLite file; `client`/`db_session` fixtures
├── test_health.py
├── test_auth.py           # login success/failure/validation/inactive-account cases
└── test_locations.py      # hierarchy listing, active-only filtering, POP detail, 404s
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
Deferred"). This does not affect per-photo GPS capture, which is a
separate, still-unbuilt PM visit module.

`Employee.assigned_district_name` remains a plain string (not a `District`
FK) — Employee Login was kept unchanged while building this module; see
the note in `app/models/employee.py` and `docs/data-model.md`.

Routers for `visits` and `dashboard` are still wired but empty. No
Google Drive integration or MIS export logic exists yet.

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
# or:   curl -X POST http://127.0.0.1:8000/api/v1/auth/login \
#         -H "Content-Type: application/json" \
#         -d '{"employee_id": "ENG001", "mobile_number": "9876543210"}'
# or:   curl http://127.0.0.1:8000/api/v1/locations/districts
```

Run tests (uses an isolated SQLite file via `tests/conftest.py` — no
Postgres needed):

```bash
pip install pytest httpx
pytest
```
