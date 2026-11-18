import io
import json
from datetime import datetime

from app.main import app
from app.services.drive import GoogleDriveUploadService, get_drive_upload_service
from app.services.drive.base import PhotoUploadItem, PhotoUploadResult, VisitMetadata
from app.services.drive.fake_drive_upload_service import FakeDriveUploadService
from app.services.drive.naming import build_drive_filename, build_drive_folder_segments
from app.services.drive.not_configured_drive_upload_service import NotConfiguredDriveUploadService


class _SpyDriveUploadService(GoogleDriveUploadService):
    """Records the VisitMetadata it was called with, so a test can
    verify which `employee_id` actually reached the Drive upload step -
    without this, a test could only see the HTTP response, not what the
    endpoint internally trusted."""

    def __init__(self) -> None:
        self.last_visit: VisitMetadata | None = None

    def upload_visit_photos(self, visit, photos):
        self.last_visit = visit
        return [
            PhotoUploadResult(
                category=photo.category,
                drive_file_id=f"spy-file-{photo.category}",
                drive_file_link="",
                duplicate=False,
            )
            for photo in photos
        ]


_MANDATORY_CATEGORIES = [
    "pop_rack",
    "ups_battery",
    "busbar",
    "earth_pit_chamber",
    "earth_pit_open_with_rod",
]


def _visit_metadata(visit_id: str = "visit-1", pop_id: int = 7) -> dict:
    return {
        "visit_id": visit_id,
        "employee_id": "ENG001",
        "pop_id": pop_id,
        "pop_code": "POP-00125",
        "district": "Chennai",
        "block": "Sholinganallur",
        "gp": "Semmancheri GP",
        "visit_date": "2026-11-17",
    }


def _photo_metadata(category: str) -> dict:
    return {
        "category": category,
        "captured_at": "2026-11-17T17:25:42",
        "latitude": 11.123456,
        "longitude": 77.654321,
        "accuracy_m": 4.2,
    }


def _post_sync(
    client, visit_id: str, visit_metadata: dict, categories: list[str], headers: dict | None = None
):
    photos_metadata = [_photo_metadata(category) for category in categories]
    files = [
        ("files", (f"{category}.jpg", io.BytesIO(b"fake-photo-bytes"), "image/jpeg"))
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


def _use_fake_drive_service(service: GoogleDriveUploadService) -> None:
    app.dependency_overrides[get_drive_upload_service] = lambda: service


def _clear_drive_override() -> None:
    app.dependency_overrides.pop(get_drive_upload_service, None)


def test_successful_upload_of_all_five_photos(client, auth_headers, seeded_pop_id):
    fake = FakeDriveUploadService()
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(pop_id=seeded_pop_id)
        response = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "synced"
        assert len(body["photos"]) == 5
        assert {p["category"] for p in body["photos"]} == set(_MANDATORY_CATEGORIES)
        assert all(not p["duplicate"] for p in body["photos"])
        assert fake.call_count == 1
    finally:
        _clear_drive_override()


def test_successful_sync_persists_a_pm_visit_record_for_the_dashboard(
    client, auth_headers, seeded_pop_id, db_session
):
    """Foundation for the District/Engineer/POP-wise dashboard (see
    app/services/pm_visits.py, app/services/compliance.py): a
    successful sync must leave a PmVisit row with all 5 PmPhoto rows,
    or there is nothing for the dashboard to aggregate."""
    from app.models.pm_photo import PmPhoto
    from app.models.pm_visit import PmVisit

    fake = FakeDriveUploadService()
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(visit_id="visit-persist-1", pop_id=seeded_pop_id)
        response = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )
        assert response.json()["status"] == "synced"

        persisted = db_session.get(PmVisit, "visit-persist-1")
        assert persisted is not None
        assert persisted.pop_id == seeded_pop_id
        assert persisted.visit_date == "2026-11-17"

        photos = (
            db_session.query(PmPhoto).filter(PmPhoto.visit_id == "visit-persist-1").all()
        )
        assert {p.category for p in photos} == set(_MANDATORY_CATEGORIES)
        assert all(p.drive_file_id for p in photos)
    finally:
        _clear_drive_override()


def test_resyncing_the_same_visit_updates_rather_than_duplicates_the_persisted_record(
    client, auth_headers, seeded_pop_id, db_session
):
    from app.models.pm_photo import PmPhoto
    from app.models.pm_visit import PmVisit

    fake = FakeDriveUploadService()
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(visit_id="visit-persist-2", pop_id=seeded_pop_id)
        _post_sync(client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers)
        _post_sync(client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers)

        assert db_session.query(PmVisit).filter(PmVisit.id == "visit-persist-2").count() == 1
        photos = (
            db_session.query(PmPhoto).filter(PmPhoto.visit_id == "visit-persist-2").all()
        )
        assert len(photos) == 5  # not 10 - replaced, not appended
    finally:
        _clear_drive_override()


def test_upload_failure_is_reported_as_a_clean_failed_response(
    client, auth_headers, seeded_pop_id
):
    fake = FakeDriveUploadService(fail=True)
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(pop_id=seeded_pop_id)
        response = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )

        assert response.status_code == 200  # the HTTP call succeeds; the sync itself failed
        body = response.json()
        assert body["status"] == "failed"
        assert "Simulated Google Drive upload failure" in body["message"]
    finally:
        _clear_drive_override()


def test_a_failed_drive_upload_persists_no_pm_visit_record(
    client, auth_headers, seeded_pop_id, db_session
):
    """A PmVisit row must only ever exist for a visit that is actually
    on Drive - never created speculatively before/regardless of the
    Drive result."""
    from app.models.pm_visit import PmVisit

    fake = FakeDriveUploadService(fail=True)
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(visit_id="visit-never-persisted", pop_id=seeded_pop_id)
        response = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )

        assert response.json()["status"] == "failed"
        assert db_session.get(PmVisit, "visit-never-persisted") is None
    finally:
        _clear_drive_override()


def test_retry_after_failure_succeeds_once_the_service_recovers(
    client, auth_headers, seeded_pop_id
):
    fake = FakeDriveUploadService(fail=True)
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(pop_id=seeded_pop_id)
        first = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )
        assert first.json()["status"] == "failed"

        fake.fail = False
        second = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )

        assert second.json()["status"] == "synced"
        assert fake.call_count == 2
    finally:
        _clear_drive_override()


def test_resyncing_the_same_visit_does_not_create_duplicate_files(
    client, auth_headers, seeded_pop_id
):
    fake = FakeDriveUploadService()
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(pop_id=seeded_pop_id)
        first = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )
        first_photos = {p["category"]: p["drive_file_id"] for p in first.json()["photos"]}

        # Simulate retrying the sync (e.g. the app wasn't sure the first
        # attempt made it to the server) with the exact same visit.
        second = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )
        second_body = second.json()

        assert second_body["status"] == "synced"
        assert all(p["duplicate"] for p in second_body["photos"])
        for photo in second_body["photos"]:
            assert photo["drive_file_id"] == first_photos[photo["category"]]
    finally:
        _clear_drive_override()


def test_not_configured_drive_service_fails_clearly(client, auth_headers, seeded_pop_id):
    _use_fake_drive_service(NotConfiguredDriveUploadService())
    try:
        visit = _visit_metadata(pop_id=seeded_pop_id)
        response = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )

        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "failed"
        assert "not configured" in body["message"].lower()
    finally:
        _clear_drive_override()


def test_mismatched_visit_id_between_path_and_metadata_is_rejected(
    client, auth_headers, seeded_pop_id
):
    fake = FakeDriveUploadService()
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(visit_id="visit-1", pop_id=seeded_pop_id)
        response = _post_sync(
            client, "visit-DIFFERENT", visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )

        assert response.json()["status"] == "failed"
        assert fake.call_count == 0
    finally:
        _clear_drive_override()


def test_mismatched_photo_count_is_rejected(client, auth_headers, seeded_pop_id):
    fake = FakeDriveUploadService()
    _use_fake_drive_service(fake)
    try:
        visit = _visit_metadata(pop_id=seeded_pop_id)
        # 5 metadata entries but only 4 files - must be rejected before
        # ever reaching the Drive service.
        photos_metadata = [_photo_metadata(category) for category in _MANDATORY_CATEGORIES]
        files = [
            ("files", (f"{category}.jpg", io.BytesIO(b"fake-photo-bytes"), "image/jpeg"))
            for category in _MANDATORY_CATEGORIES[:4]
        ]
        response = client.post(
            f"/api/v1/visits/{visit['visit_id']}/sync",
            data={
                "visit_metadata": json.dumps(visit),
                "photos_metadata": json.dumps(photos_metadata),
            },
            files=files,
            headers=auth_headers,
        )

        assert response.json()["status"] == "failed"
        assert fake.call_count == 0
    finally:
        _clear_drive_override()


def test_visits_sync_rejects_anonymous_requests(client):
    """Regression test for the audit finding that /visits/{id}/sync was
    previously reachable with no token at all."""
    visit = _visit_metadata()
    response = _post_sync(client, visit["visit_id"], visit, _MANDATORY_CATEGORIES)

    assert response.status_code == 401


def test_employee_id_sent_to_drive_comes_from_the_verified_jwt_not_the_request_body(
    client, auth_headers, seeded_pop_id
):
    """The Flutter app's own `visit_metadata.employee_id` must never be
    trusted for identity - this proves the endpoint uses
    `current_employee.employee_code` (from the JWT) instead, even when
    the request body claims to be a different employee."""
    spy = _SpyDriveUploadService()
    _use_fake_drive_service(spy)
    try:
        visit = _visit_metadata(pop_id=seeded_pop_id)
        visit["employee_id"] = "SPOOFED-EMPLOYEE-ID"  # auth_headers is logged in as ENG001

        response = _post_sync(
            client, visit["visit_id"], visit, _MANDATORY_CATEGORIES, headers=auth_headers
        )

        assert response.json()["status"] == "synced"
        assert spy.last_visit is not None
        assert spy.last_visit.employee_id == "ENG001"
    finally:
        _clear_drive_override()


def test_folder_path_generation_matches_the_required_structure():
    visit = VisitMetadata(
        visit_id="visit-1",
        employee_id="ENG001",
        pop_id=7,
        pop_code="POP-00125",
        district="Chennai",
        block="Sholinganallur",
        gp="Semmancheri GP",
        visit_date="2026-11-17",
    )

    segments = build_drive_folder_segments(visit, "TANFINET PM Monitoring")

    assert segments == [
        "TANFINET PM Monitoring",
        "Chennai",
        "Sholinganallur",
        "Semmancheri GP",
        "POP-00125",
        "PM Visits",
        "2026-11-17",
        "visit-1",
    ]


def test_file_naming_convention_matches_the_documented_example():
    filename = build_drive_filename("POP-00125", "pop_rack", datetime(2026, 11, 17, 17, 25, 42))

    assert filename == "POP-00125_POP-RACK_2026-11-17_172542.jpg"


def test_file_naming_sanitizes_unsafe_characters_in_the_pop_code():
    filename = build_drive_filename("POP 00125/X", "busbar", datetime(2026, 1, 1, 9, 0, 0))

    assert filename == "POP-00125-X_BUSBAR_2026-01-01_090000.jpg"


def test_fake_drive_service_directly_tracks_idempotency_per_folder():
    fake = FakeDriveUploadService()
    visit = VisitMetadata(
        visit_id="visit-1",
        employee_id="ENG001",
        pop_id=7,
        pop_code="POP-00125",
        district="Chennai",
        block="Sholinganallur",
        gp="Semmancheri GP",
        visit_date="2026-11-17",
    )
    photo = PhotoUploadItem(
        category="pop_rack",
        captured_at="2026-11-17T17:25:42",
        latitude=11.1,
        longitude=77.2,
        accuracy_m=4.0,
        filename="POP-00125_POP-RACK_2026-11-17_172542.jpg",
        content=b"fake-bytes",
    )

    first = fake.upload_visit_photos(visit, [photo])
    second = fake.upload_visit_photos(visit, [photo])

    assert first[0].duplicate is False
    assert second[0].duplicate is True
    assert first[0].drive_file_id == second[0].drive_file_id
