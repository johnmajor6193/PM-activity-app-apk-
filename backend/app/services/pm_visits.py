from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.pm_photo import PmPhoto
from app.models.pm_visit import PmVisit
from app.services.drive.base import PhotoUploadItem, PhotoUploadResult, VisitMetadata


def record_synced_visit(
    db: Session,
    *,
    employee_id: int,
    visit: VisitMetadata,
    photos: list[PhotoUploadItem],
    results: list[PhotoUploadResult],
) -> None:
    """Persists that `visit` was successfully synced to Google Drive,
    so the dashboard (app/api/v1/endpoints/dashboard.py) has something
    to aggregate.

    Called from POST /visits/{visit_id}/sync
    (app/api/v1/endpoints/visits.py) only *after*
    drive_service.upload_visit_photos has already succeeded for every
    photo — never on a failed or skipped sync, and never before the
    Drive result exists. `employee_id` is the verified JWT identity's
    numeric Employee.id (see app/api/deps.py), not anything from the
    request body.

    Upserts rather than inserts: re-syncing the same visit_id (a
    retried sync — the same case the Drive-level idempotency already
    handles) replaces the existing row's photos rather than creating a
    duplicate PmVisit. Raises on a database error (e.g. an invalid
    pop_id) — the caller turns that into a clean "failed" response,
    same as a Drive failure.
    """
    now = datetime.now(timezone.utc)
    pm_visit = db.get(PmVisit, visit.visit_id)
    if pm_visit is None:
        pm_visit = PmVisit(
            id=visit.visit_id,
            employee_id=employee_id,
            pop_id=visit.pop_id,
            visit_date=visit.visit_date,
            first_synced_at=now,
            last_synced_at=now,
        )
        db.add(pm_visit)
    else:
        pm_visit.employee_id = employee_id
        pm_visit.pop_id = visit.pop_id
        pm_visit.visit_date = visit.visit_date
        pm_visit.last_synced_at = now
        pm_visit.photos.clear()

    for photo, result in zip(photos, results, strict=True):
        pm_visit.photos.append(
            PmPhoto(
                visit_id=visit.visit_id,
                category=photo.category,
                captured_at=photo.captured_at,
                gps_lat=photo.latitude,
                gps_lng=photo.longitude,
                gps_accuracy_m=photo.accuracy_m,
                drive_file_id=result.drive_file_id,
                drive_file_link=result.drive_file_link,
            )
        )

    db.commit()
