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
   - Capture GPS location + accuracy for every photo, validated against the
     POP's geofence
   - Work fully offline and sync later
2. **`backend/`** — Python FastAPI service that:
   - Authenticates engineers
   - Stores District/Block/GP/POP master data
   - Stores PM visit records (GPS, timestamps, photo metadata, Google Drive
     links)
   - Will later expose dashboards (district-wise, engineer-wise, POP-wise)
     and Monthly MIS / Excel export

A web admin dashboard will be added in a later phase once the mobile app and
backend are functional.

## Technology Stack (locked)

| Layer | Technology |
|---|---|
| Mobile app | Flutter / Dart, Android-first, clean modular architecture |
| Backend | Python, FastAPI, PostgreSQL, REST API |
| Photo storage | Google Drive API (no Firebase) |
| Visit/metadata storage | PostgreSQL (GPS, timestamps, photo metadata, Drive links) |

Google Drive folder convention for the 5 PM photographs:

```
TANFINET_POP_PM_VISIT
└── <District>
    └── <Block>
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

No GPS watermark, Google Drive upload, offline *sync* (local storage
exists; syncing it to a server does not), geofencing, dashboard, MIS,
or final visit submission has been implemented yet. See
`mobile_app/README.md` and `backend/README.md` for details and how to
run each part.
