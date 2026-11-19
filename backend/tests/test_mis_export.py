"""Tests for the Monthly MIS / Excel export module
(app/services/mis_export.py, app/api/v1/endpoints/mis.py).

Same seeded dev hierarchy as test_dashboard.py: Chennai has 3 *active*
POPs (POP-CHN-001, POP-CHN-003, POP-CHN-004 - POP-CHN-002 is seeded
inactive and must never appear), Madurai has 1 (POP-MDU-001). Visits
are synced through the real POST /visits/{id}/sync endpoint.

Uses August 2029 throughout - a month no other test file in this
suite ever syncs a visit into, since every test here shares one
persistent SQLite file across the whole pytest session (see
conftest.py) rather than a fresh/rolled-back one per test.
"""

import csv
import io
import json
from datetime import date

from openpyxl import load_workbook

from app.main import app
from app.models.pop import Pop
from app.services.drive import get_drive_upload_service
from app.services.drive.fake_drive_upload_service import FakeDriveUploadService
from app.services.mis_export import COLUMNS, build_mis_rows, month_bounds, rows_to_csv, rows_to_xlsx

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
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _sync_visit(client, headers: dict, *, visit_id: str, pop_id: int, visit_date: str, categories: list[str]):
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
        ("files", (f"{category}.jpg", io.BytesIO(b"fake-bytes"), "image/jpeg")) for category in categories
    ]
    return client.post(
        f"/api/v1/visits/{visit_id}/sync",
        data={"visit_metadata": json.dumps(visit_metadata), "photos_metadata": json.dumps(photos_metadata)},
        files=files,
        headers=headers,
    )


def _use_fake_drive_service() -> None:
    app.dependency_overrides[get_drive_upload_service] = lambda: FakeDriveUploadService()


def _clear_drive_override() -> None:
    app.dependency_overrides.pop(get_drive_upload_service, None)


# ---- month_bounds (pure) ----


def test_month_bounds_30_day_month():
    assert month_bounds(2029, 4) == (date(2029, 4, 1), date(2029, 4, 30))


def test_month_bounds_31_day_month():
    assert month_bounds(2029, 8) == (date(2029, 8, 1), date(2029, 8, 31))


def test_month_bounds_february_leap_year():
    assert month_bounds(2028, 2) == (date(2028, 2, 1), date(2028, 2, 29))


def test_month_bounds_february_non_leap_year():
    assert month_bounds(2029, 2) == (date(2029, 2, 1), date(2029, 2, 28))


def test_month_bounds_december_rolls_into_the_same_year():
    assert month_bounds(2029, 12) == (date(2029, 12, 1), date(2029, 12, 31))


# ---- build_mis_rows ----


def test_no_visits_returns_one_pending_row_per_active_pop_and_excludes_inactive(client, db_session):
    start, end = month_bounds(2029, 8)
    rows = build_mis_rows(db_session, start, end)

    pop_codes = {row.pop_code for row in rows}
    assert "POP-CHN-001" in pop_codes
    assert "POP-CHN-003" in pop_codes
    assert "POP-CHN-004" in pop_codes
    assert "POP-MDU-001" in pop_codes
    assert "POP-CHN-002" not in pop_codes  # seeded inactive

    for row in rows:
        if row.pop_code in {"POP-CHN-001", "POP-CHN-003", "POP-CHN-004", "POP-MDU-001"}:
            assert row.visit_status == "Pending"
            assert row.sync_status == "Not Synced"
            assert row.overall_compliance == ""
            assert row.visit_id is None
            assert row.employee_id is None
            assert row.categories_present == ""
            assert row.categories_missing == "busbar, earth_pit_chamber, earth_pit_open_with_rod, pop_rack, ups_battery"


def test_full_compliant_visit_produces_a_completed_compliant_row(client, db_session):
    _use_fake_drive_service()
    try:
        headers = _login(client, "ENG001", "9876543210")
        pop_id = _pop_id(db_session, "POP-CHN-001")
        response = _sync_visit(
            client, headers, visit_id="mis-visit-1", pop_id=pop_id, visit_date="2029-08-10", categories=_FULL_CATEGORIES
        )
        assert response.json()["status"] == "synced"

        start, end = month_bounds(2029, 8)
        rows = build_mis_rows(db_session, start, end, pop_id=pop_id)

        assert len(rows) == 1
        row = rows[0]
        assert row.visit_id == "mis-visit-1"
        assert row.visit_date == "2029-08-10"
        assert row.employee_id == "ENG001"
        assert row.employee_name == "Dev Test Engineer"
        assert row.district_name == "Chennai"
        assert row.block_name == "Sholinganallur"
        assert row.gp_name == "Semmancheri GP"
        assert row.pop_code == "POP-CHN-001"
        assert row.visit_status == "Completed"
        assert row.overall_compliance == "Compliant"
        assert row.sync_status == "Synced"
        assert row.categories_missing == ""
        assert row.first_synced_at is not None
        assert row.last_synced_at is not None
    finally:
        _clear_drive_override()


def test_partial_visit_produces_a_completed_incomplete_row_with_missing_categories(client, db_session):
    _use_fake_drive_service()
    try:
        headers = _login(client, "ENG002", "9123456780")
        pop_id = _pop_id(db_session, "POP-CHN-003")
        _sync_visit(
            client, headers, visit_id="mis-visit-2", pop_id=pop_id, visit_date="2029-08-11", categories=_PARTIAL_CATEGORIES
        )

        start, end = month_bounds(2029, 8)
        rows = build_mis_rows(db_session, start, end, pop_id=pop_id)

        assert len(rows) == 1
        row = rows[0]
        assert row.visit_status == "Completed"
        assert row.overall_compliance == "Incomplete"
        # category_breakdown sorts alphabetically, not by submission order.
        assert row.categories_present == "busbar, pop_rack, ups_battery"
        assert row.categories_missing == "earth_pit_chamber, earth_pit_open_with_rod"
    finally:
        _clear_drive_override()


def test_multiple_visits_to_the_same_pop_produce_multiple_rows_not_one(client, db_session):
    _use_fake_drive_service()
    try:
        headers = _login(client, "ENG001", "9876543210")
        pop_id = _pop_id(db_session, "POP-CHN-004")
        _sync_visit(
            client, headers, visit_id="mis-visit-3a", pop_id=pop_id, visit_date="2029-08-02", categories=_FULL_CATEGORIES
        )
        _sync_visit(
            client, headers, visit_id="mis-visit-3b", pop_id=pop_id, visit_date="2029-08-16", categories=_PARTIAL_CATEGORIES
        )

        start, end = month_bounds(2029, 8)
        rows = build_mis_rows(db_session, start, end, pop_id=pop_id)

        assert len(rows) == 2  # a real ledger, not deduped to one row per POP
        visit_ids = {row.visit_id for row in rows}
        assert visit_ids == {"mis-visit-3a", "mis-visit-3b"}
        assert all(row.visit_status == "Completed" for row in rows)
    finally:
        _clear_drive_override()


def test_a_visit_outside_the_requested_month_is_excluded_and_the_pop_shows_pending(client, db_session):
    _use_fake_drive_service()
    try:
        headers = _login(client, "ENG001", "9876543210")
        pop_id = _pop_id(db_session, "POP-MDU-001")
        _sync_visit(
            client, headers, visit_id="mis-visit-4", pop_id=pop_id, visit_date="2029-07-31", categories=_FULL_CATEGORIES
        )

        start, end = month_bounds(2029, 8)  # August, the visit above is in July
        rows = build_mis_rows(db_session, start, end, pop_id=pop_id)

        assert len(rows) == 1
        assert rows[0].visit_status == "Pending"
        assert rows[0].visit_id is None
    finally:
        _clear_drive_override()


def test_district_filter_only_returns_pops_in_that_district(db_session):
    from app.models.district import District

    chennai_id = db_session.query(District).filter(District.name == "Chennai").one().id
    start, end = month_bounds(2029, 8)

    rows = build_mis_rows(db_session, start, end, district_id=chennai_id)

    assert {row.pop_code for row in rows} == {"POP-CHN-001", "POP-CHN-003", "POP-CHN-004"}


def test_pop_id_filter_returns_exactly_that_pop(db_session):
    start, end = month_bounds(2029, 8)
    pop_id = _pop_id(db_session, "POP-MDU-001")

    rows = build_mis_rows(db_session, start, end, pop_id=pop_id)

    assert len(rows) == 1
    assert rows[0].pop_code == "POP-MDU-001"


def test_employee_filter_shows_only_that_employees_visits_and_suppresses_pending_rows(client, db_session):
    # Scoped to its own POP (POP-MDU-001) so this test is unaffected by
    # other tests' visits to the Chennai POPs earlier in this file -
    # every test here shares one persistent SQLite file (see
    # conftest.py), so "no other test ever touches this POP" is what
    # actually isolates it, not the employee filter alone.
    _use_fake_drive_service()
    try:
        eng001 = _login(client, "ENG001", "9876543210")
        eng002 = _login(client, "ENG002", "9123456780")
        pop_id = _pop_id(db_session, "POP-MDU-001")
        _sync_visit(
            client, eng001, visit_id="mis-visit-5a", pop_id=pop_id, visit_date="2029-08-05", categories=_FULL_CATEGORIES
        )
        _sync_visit(
            client, eng002, visit_id="mis-visit-5b", pop_id=pop_id, visit_date="2029-08-06", categories=_FULL_CATEGORIES
        )

        start, end = month_bounds(2029, 8)
        rows = build_mis_rows(db_session, start, end, pop_id=pop_id, employee_code="ENG001")

        # Only ENG001's own visit, never ENG002's, and no "Pending"
        # placeholder row even though this query is POP-scoped.
        assert len(rows) == 1
        assert rows[0].visit_id == "mis-visit-5a"
        assert rows[0].employee_id == "ENG001"
        assert all(row.visit_status != "Pending" for row in rows)
    finally:
        _clear_drive_override()


def test_unknown_employee_id_returns_no_rows_not_an_error(db_session):
    start, end = month_bounds(2029, 8)

    rows = build_mis_rows(db_session, start, end, employee_code="DOES-NOT-EXIST")

    assert rows == []


# ---- CSV / XLSX serialization ----


def test_rows_to_csv_round_trips_cleanly_through_a_real_csv_parser():
    start, end = month_bounds(2029, 8)
    # Build directly from an empty DB-independent scenario via a tiny
    # in-memory row instead of a full sync, to keep this test about
    # the serializer only.
    from app.services.mis_export import MisRow

    rows = [
        MisRow(
            visit_id="v1",
            visit_date="2029-08-10",
            employee_id="ENG001",
            employee_name="Dev Test Engineer",
            district_name="Chennai",
            block_name="Sholinganallur",
            gp_name="Semmancheri GP",
            pop_code="POP-CHN-001",
            pop_name="Semmancheri POP 1",
            visit_status="Completed",
            categories_present="pop_rack, ups_battery",
            categories_missing="busbar, earth_pit_chamber, earth_pit_open_with_rod",
            overall_compliance="Incomplete",
            sync_status="Synced",
            first_synced_at="2029-08-10T10:00:00",
            last_synced_at="2029-08-10T10:00:00",
        )
    ]

    csv_text = rows_to_csv(rows)
    parsed = list(csv.reader(io.StringIO(csv_text)))

    assert parsed[0] == COLUMNS
    assert parsed[1][0] == "v1"
    assert parsed[1][4] == "Chennai"
    # A field containing a comma must still parse back as one field.
    assert parsed[1][10] == "pop_rack, ups_battery"
    assert parsed[1][11] == "busbar, earth_pit_chamber, earth_pit_open_with_rod"


def test_rows_to_xlsx_produces_a_workbook_a_real_spreadsheet_app_can_open():
    from app.services.mis_export import MisRow

    rows = [
        MisRow(
            visit_id=None,
            visit_date=None,
            employee_id=None,
            employee_name=None,
            district_name="Madurai",
            block_name="Thiruparankundram",
            gp_name="Avaniyapuram GP",
            pop_code="POP-MDU-001",
            pop_name="Avaniyapuram POP 1",
            visit_status="Pending",
            categories_present="",
            categories_missing="busbar, earth_pit_chamber, earth_pit_open_with_rod, pop_rack, ups_battery",
            overall_compliance="",
            sync_status="Not Synced",
            first_synced_at=None,
            last_synced_at=None,
        )
    ]

    content = rows_to_xlsx(rows)
    workbook = load_workbook(io.BytesIO(content))
    sheet = workbook.active

    header = [cell.value for cell in sheet[1]]
    assert header == COLUMNS
    data_row = [cell.value for cell in sheet[2]]
    assert data_row[4] == "Madurai"
    assert data_row[9] == "Pending"


# ---- endpoint-level ----


def test_export_endpoint_rejects_anonymous_requests(client):
    response = client.get("/api/v1/mis/export?year=2029&month=8")

    assert response.status_code == 401


def test_export_endpoint_rejects_an_invalid_format(client, auth_headers):
    response = client.get("/api/v1/mis/export?year=2029&month=8&format=pdf", headers=auth_headers)

    assert response.status_code == 422


def test_export_endpoint_csv_has_the_right_content_type_and_filename(client, auth_headers):
    response = client.get("/api/v1/mis/export?year=2029&month=8&format=csv", headers=auth_headers)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/csv")
    assert 'filename="mis_export_2029-08.csv"' in response.headers["content-disposition"]
    body = response.content.decode("utf-8-sig")
    assert body.splitlines()[0] == ",".join(COLUMNS)


def test_export_endpoint_xlsx_has_the_right_content_type_and_is_a_valid_workbook(client, auth_headers):
    response = client.get("/api/v1/mis/export?year=2029&month=8&format=xlsx", headers=auth_headers)

    assert response.status_code == 200
    assert response.headers["content-type"] == (
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    assert 'filename="mis_export_2029-08.xlsx"' in response.headers["content-disposition"]
    workbook = load_workbook(io.BytesIO(response.content))
    header = [cell.value for cell in workbook.active[1]]
    assert header == COLUMNS


def test_export_endpoint_defaults_to_csv_when_format_is_omitted(client, auth_headers):
    response = client.get("/api/v1/mis/export?year=2029&month=8", headers=auth_headers)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/csv")
