# backend — TANFINET POP PM Monitoring API (FastAPI)

REST API backend: employee auth, District/Block/GP/POP master data, PM
visit records (GPS, timestamps, photo metadata, Google Drive links), and
later, compliance dashboards and MIS export.

## Structure

```
app/
├── main.py              # FastAPI app instance, router wiring, /health
├── core/
│   └── config.py        # settings (env vars / .env)
├── api/v1/
│   ├── router.py        # aggregates all v1 routers
│   └── endpoints/       # auth, locations, visits, dashboard (empty routers for now)
├── models/              # SQLAlchemy ORM models (added in a later step)
├── schemas/             # Pydantic request/response schemas (added in a later step)
├── db/
│   ├── base.py           # declarative base
│   └── session.py        # SQLAlchemy engine/session
└── services/             # business logic: compliance calc, Drive upload, MIS export (later step)
tests/
└── test_health.py
```

## Status

Scaffold only. Routers for `auth`, `locations`, `visits`, and `dashboard`
are wired into the app but currently define no endpoints. The only live
endpoint is `GET /health`, used to confirm the app boots correctly.

No database models, authentication, Google Drive integration, or MIS
export logic exists yet — see `docs/data-model.md` for the planned schema.

## Running locally (next step)

Requires Python 3.11+ and a PostgreSQL instance (not required just to run
the health check, since no DB code executes on startup yet).

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # edit DATABASE_URL if needed

uvicorn app.main:app --reload
# then: curl http://127.0.0.1:8000/health
```

Run tests:

```bash
pip install pytest
pytest
```
