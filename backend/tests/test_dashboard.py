"""Tests for the District/Engineer/POP-wise dashboard
(app/api/v1/endpoints/dashboard.py, app/services/compliance.py).

These rely on the seeded dev hierarchy (app/db/seed_dev_data.py):
Chennai has 3 *active* POPs (POP-CHN-001, POP-CHN-003, POP-CHN-004 -
POP-CHN-002 is seeded inactive and must never count), Madurai has 1
(POP-MDU-001). A visit is synced through the real
POST /visits/{id}/sync endpoint (not inserted directly), so these also
exercise app/services/pm_visits.py end to end.
"""

import io
import json
from datetime import date

from app.main import app
from app.models.pm_photo import PmPhoto
from app.models.pm_visit import PmVisit
from app.models.pop import Pop
from app.services.compliance import category_breakdown, fortnight_bounds, is_compliant
from app.services.drive import get_drive_upload_service
from app.services.drive.fake_drive_upload_service import FakeDriveUploadService

_FULL_CATEGORIES = [
    "pop_rack",
    "ups_battery",
    "busbar",
    "earth_pit_chamber",
    "earth_pit_open_with_rod",
]
_PARTIAL_CATEGORIES = ["pop_rack", "ups_battery", "busbar"]


def _pop_id(db_session, pop_code: str) -> int:
    return db_session.query(Pop).filter(Pop.pop_code == pop_code).one().id


def _login(client, employee_id: str, mobile_number: str) -> dict:
    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": employee_id, "mobile_number": mobile_number},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _sync_visit(
    client, headers: dict, *, visit_id: str, pop_id: int, visit_date: str, categories: list[str]
):
    visit_metadata = {
        "visit_id": visit_id,
        "employee_id": "ignored-by-the-endpoint",
        "pop_id": pop_id,
        "pop_code": "whatever",
        "district": "whatever",
        "block": "whatever",
        "gp": "whatever",
        "visit_date": visit_date,
    }
    photos_metadata = [
        {
            "category": category,
            "captured_at": f"{visit_date}T10:00:00",
            "latitude": 11.1,
            "longitude": 77.2,
            "accuracy_m": 4.0,
        }
        for category in categories
    ]
    files = [
        ("files", (f"{category}.jpg", io.BytesIO(b"fake-bytes"), "image/jpeg"))
        for category in categories
    ]
    return client.post(
        f"/api/v1/visits/{visit_id}/sync",
        data={
            "visit_metadata": json.dumps(visit_metadata),
            "photos_metadata": json.dumps(photos_metadata),
        },
        files=files,
        headers=headers,
    )


def _use_fake_drive_service() -> None:
    app.dependency_overrides[get_drive_upload_service] = lambda: FakeDriveUploadService()


def _clear_drive_override() -> None:
    app.dependency_overrides.pop(get_drive_upload_service, None)


def test_fortnight_bounds_first_half_of_month():
    assert fortnight_bounds(date(2028, 3, 1)) == (date(2028, 3, 1), date(2028, 3, 15))
    assert fortnight_bounds(date(2028, 3, 15)) == (date(2028, 3, 1), date(2028, 3, 15))


def test_fortnight_bounds_second_half_of_a_31_day_month():
    assert fortnight_bounds(date(2028, 3, 16)) == (date(2028, 3, 16), date(2028, 3, 31))
    assert fortnight_bounds(date(2028, 3, 31)) == (date(2028, 3, 16), date(2028, 3, 31))


def test_fortnight_bounds_second_half_of_a_30_day_month():
    assert fortnight_bounds(date(2028, 4, 20)) == (date(2028, 4, 16), date(2028, 4, 30))


def test_fortnight_bounds_second_half_of_february_in_a_leap_year():
    assert fortnight_bounds(date(2028, 2, 20)) == (date(2028, 2, 16), date(2028, 2, 29))


def test_fortnight_bounds_second_half_of_february_in_a_non_leap_year():
    assert fortnight_bounds(date(2027, 2, 20)) == (date(2027, 2, 16), date(2027, 2, 28))


def test_fortnight_bounds_second_half_of_december_rolls_into_the_same_year():
    assert fortnight_bounds(date(2026, 12, 20)) == (date(2026, 12, 16), date(2026, 12, 31))


def _fake_visit(categories: list[str]) -> PmVisit:
    """An in-memory PmVisit, never persisted - enough to exercise the
    pure category_breakdown/is_compliant functions directly."""
    visit = PmVisit(id="fake", employee_id=1, pop_id=1, visit_date="2026-01-01")
    visit.photos = [
        PmPhoto(visit_id="fake", category=category, captured_at="2026-01-01T09:00:00")
        for category in categories
    ]
    return visit


def test_category_breakdown_all_five_present():
    present, missing = category_breakdown(_fake_visit(_FULL_CATEGORIES))

    assert present == sorted(_FULL_CATEGORIES)
    assert missing == []


def test_category_breakdown_some_missing():
    present, missing = category_breakdown(_fake_visit(_PARTIAL_CATEGORIES))

    assert present == sorted(_PARTIAL_CATEGORIES)
    assert missing == ["earth_pit_chamber", "earth_pit_open_with_rod"]


def test_category_breakdown_none_present():
    present, missing = category_breakdown(_fake_visit([]))

    assert present == []
    assert missing == sorted(_FULL_CATEGORIES)


def test_is_compliant_matches_category_breakdown():
    assert is_compliant(_fake_visit(_FULL_CATEGORIES)) is True
    assert is_compliant(_fake_visit(_PARTIAL_CATEGORIES)) is False
    assert is_compliant(_fake_visit([])) is False


def test_district_dashboard_reports_compliance_percent_for_active_pops_only(
    client, db_session
):
    """POP-CHN-001 gets a full 5/5 visit (compliant), POP-CHN-003 gets
    only 3/5 (visited but not compliant), POP-CHN-004 is never
    visited, and inactive POP-CHN-002 must not be counted at all."""
    _use_fake_drive_service()
    try:
        eng001 = _login(client, "ENG001", "9876543210")
        eng002 = _login(client, "ENG002", "9123456780")

        # A dedicated fortnight (Mar 2028) no other test in the suite
        # uses, so this is correct regardless of test execution order
        # (every test here shares one persistent SQLite file - see
        # conftest.py - rather than a fresh/rolled-back one per test).
        _sync_visit(
            client,
            eng001,
            visit_id="dash-visit-1",
            pop_id=_pop_id(db_session, "POP-CHN-001"),
            visit_date="2028-03-17",
            categories=_FULL_CATEGORIES,
        )
        _sync_visit(
            client,
            eng002,
            visit_id="dash-visit-2",
            pop_id=_pop_id(db_session, "POP-CHN-003"),
            visit_date="2028-03-18",
            categories=_PARTIAL_CATEGORIES,
        )

        response = client.get("/api/v1/dashboard/districts?date=2028-03-17", headers=eng001)

        assert response.status_code == 200
        body = response.json()
        assert body["period_start"] == "2028-03-16"
        assert body["period_end"] == "2028-03-31"

        chennai = next(d for d in body["districts"] if d["district_name"] == "Chennai")
        assert chennai["total_active_pops"] == 3
        assert chennai["compliant_pops"] == 1
        assert chennai["compliance_percent"] == round(1 / 3 * 100, 1)

        # Completed-vs-pending: 2 of the 3 active Chennai POPs have a
        # synced visit this fortnight (one full, one partial) - that is
        # "completed" regardless of category completeness, which is a
        # separate axis (is_compliant / categories_present/missing).
        assert chennai["completed_pops"] == 2
        assert chennai["pending_pops"] == 1

        pops_by_code = {p["pop_code"]: p for p in chennai["pops"]}

        full = pops_by_code["POP-CHN-001"]
        assert full["status"] == "completed"
        assert full["is_compliant"] is True
        assert full["latest_visit_id"] == "dash-visit-1"
        assert full["categories_present"] == sorted(_FULL_CATEGORIES)
        assert full["categories_missing"] == []

        partial = pops_by_code["POP-CHN-003"]
        assert partial["status"] == "completed"  # visited, just not compliant
        assert partial["is_compliant"] is False
        assert partial["latest_visit_id"] == "dash-visit-2"
        assert partial["categories_present"] == sorted(_PARTIAL_CATEGORIES)
        assert partial["categories_missing"] == ["earth_pit_chamber", "earth_pit_open_with_rod"]

        never_visited = pops_by_code["POP-CHN-004"]
        assert never_visited["status"] == "pending"
        assert never_visited["is_compliant"] is False
        assert never_visited["latest_visit_id"] is None
        assert never_visited["categories_present"] == []
        assert never_visited["categories_missing"] == sorted(_FULL_CATEGORIES)

        # The inactive POP must not appear in the per-POP breakdown at all.
        assert "POP-CHN-002" not in pops_by_code

        madurai = next(d for d in body["districts"] if d["district_name"] == "Madurai")
        assert madurai["total_active_pops"] == 1
        assert madurai["compliant_pops"] == 0
        assert madurai["compliance_percent"] == 0.0
        assert madurai["completed_pops"] == 0
        assert madurai["pending_pops"] == 1
        assert madurai["pops"][0]["status"] == "pending"
    finally:
        _clear_drive_override()


def test_district_dashboard_excludes_visits_outside_the_fortnight(client, db_session):
    # A dedicated fortnight pair (Apr 2028) not touched by any other
    # test in this file or test_drive_sync.py - the whole suite shares
    # one persistent SQLite file across tests (see conftest.py), so
    # windows that overlap another test's dates would see its data too.
    _use_fake_drive_service()
    try:
        eng001 = _login(client, "ENG001", "9876543210")
        _sync_visit(
            client,
            eng001,
            visit_id="dash-visit-outside-window",
            pop_id=_pop_id(db_session, "POP-CHN-001"),
            visit_date="2028-04-01",  # 1st-15th fortnight
            categories=_FULL_CATEGORIES,
        )

        response = client.get("/api/v1/dashboard/districts?date=2028-04-20", headers=eng001)

        chennai = next(d for d in response.json()["districts"] if d["district_name"] == "Chennai")
        assert chennai["compliant_pops"] == 0  # the synced visit is in the 1st-15th, not 16th-31st
    finally:
        _clear_drive_override()


def test_engineer_dashboard_counts_visits_and_compliance_per_employee(client, db_session):
    # Own dedicated fortnight (Jan 2027), isolated from every other
    # test's dates for the same reason noted above.
    _use_fake_drive_service()
    try:
        eng001 = _login(client, "ENG001", "9876543210")
        eng002 = _login(client, "ENG002", "9123456780")

        _sync_visit(
            client,
            eng001,
            visit_id="dash-eng-visit-1",
            pop_id=_pop_id(db_session, "POP-CHN-001"),
            visit_date="2027-01-17",
            categories=_FULL_CATEGORIES,
        )
        _sync_visit(
            client,
            eng002,
            visit_id="dash-eng-visit-2",
            pop_id=_pop_id(db_session, "POP-CHN-003"),
            visit_date="2027-01-18",
            categories=_PARTIAL_CATEGORIES,
        )

        response = client.get("/api/v1/dashboard/engineers?date=2027-01-17", headers=eng001)

        assert response.status_code == 200
        engineers = {e["employee_id"]: e for e in response.json()["engineers"]}
        assert engineers["ENG001"]["visits_synced"] == 1
        assert engineers["ENG001"]["compliant_visits"] == 1
        assert engineers["ENG002"]["visits_synced"] == 1
        assert engineers["ENG002"]["compliant_visits"] == 0
    finally:
        _clear_drive_override()


def test_engineer_dashboard_lists_employees_with_zero_visits_too(client):
    # A fortnight nothing else in the suite ever syncs into - proves a
    # zero-visit employee still appears, not just that the endpoint works.
    response = client.get(
        "/api/v1/dashboard/engineers?date=2030-06-20",
        headers=_login(client, "ENG001", "9876543210"),
    )

    engineers = {e["employee_id"]: e for e in response.json()["engineers"]}
    assert engineers["ENG002"]["visits_synced"] == 0
    assert engineers["ENG002"]["compliant_visits"] == 0


def test_pop_visit_history_is_most_recent_first_and_flags_compliance(client, db_session):
    _use_fake_drive_service()
    try:
        eng001 = _login(client, "ENG001", "9876543210")
        pop_id = _pop_id(db_session, "POP-CHN-004")

        _sync_visit(
            client,
            eng001,
            visit_id="dash-history-older",
            pop_id=pop_id,
            visit_date="2026-10-01",
            categories=_PARTIAL_CATEGORIES,
        )
        _sync_visit(
            client,
            eng001,
            visit_id="dash-history-newer",
            pop_id=pop_id,
            visit_date="2026-11-05",
            categories=_FULL_CATEGORIES,
        )

        response = client.get(f"/api/v1/dashboard/pops/{pop_id}/visits", headers=eng001)

        assert response.status_code == 200
        visits = response.json()
        assert visits[0]["visit_id"] == "dash-history-newer"
        assert visits[0]["status"] == "completed"
        assert visits[0]["is_compliant"] is True
        assert visits[0]["photo_count"] == 5
        assert visits[0]["categories_present"] == sorted(_FULL_CATEGORIES)
        assert visits[0]["categories_missing"] == []
        assert visits[1]["visit_id"] == "dash-history-older"
        assert visits[1]["status"] == "completed"
        assert visits[1]["is_compliant"] is False
        assert visits[1]["photo_count"] == 3
        assert visits[1]["categories_present"] == sorted(_PARTIAL_CATEGORIES)
        assert visits[1]["categories_missing"] == ["earth_pit_chamber", "earth_pit_open_with_rod"]
        assert visits[0]["employee_id"] == "ENG001"
        assert visits[0]["employee_name"] == "Dev Test Engineer"
    finally:
        _clear_drive_override()


def test_pop_visit_history_for_unknown_pop_returns_404(client):
    response = client.get(
        "/api/v1/dashboard/pops/999999/visits",
        headers=_login(client, "ENG001", "9876543210"),
    )

    assert response.status_code == 404


def test_pop_visit_history_for_pop_with_no_visits_is_an_empty_list(client, db_session):
    pop_id = _pop_id(db_session, "POP-MDU-001")

    response = client.get(
        f"/api/v1/dashboard/pops/{pop_id}/visits",
        headers=_login(client, "ENG001", "9876543210"),
    )

    assert response.status_code == 200
    assert response.json() == []


def test_district_and_engineer_dashboards_default_to_todays_fortnight_when_date_is_omitted(
    client,
):
    """The `date` query param is optional on both endpoints - this
    only proves omitting it doesn't error; see fortnight_bounds'
    direct unit tests above for the date math itself."""
    headers = _login(client, "ENG001", "9876543210")

    districts_response = client.get("/api/v1/dashboard/districts", headers=headers)
    engineers_response = client.get("/api/v1/dashboard/engineers", headers=headers)

    assert districts_response.status_code == 200
    assert engineers_response.status_code == 200
    today_start, today_end = fortnight_bounds(date.today())
    assert districts_response.json()["period_start"] == today_start.isoformat()
    assert engineers_response.json()["period_end"] == today_end.isoformat()


def test_district_dashboard_rejects_anonymous_requests(client):
    response = client.get("/api/v1/dashboard/districts")

    assert response.status_code == 401


def test_engineer_dashboard_rejects_anonymous_requests(client):
    response = client.get("/api/v1/dashboard/engineers")

    assert response.status_code == 401


def test_pop_visit_history_rejects_anonymous_requests(client, db_session):
    pop_id = _pop_id(db_session, "POP-CHN-001")

    response = client.get(f"/api/v1/dashboard/pops/{pop_id}/visits")

    assert response.status_code == 401
