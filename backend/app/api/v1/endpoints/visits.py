import json
from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.deps import get_current_employee
from app.models.employee import Employee
from app.schemas.drive_sync import PhotoSyncMetadata, PhotoSyncResult, VisitSyncMetadata, VisitSyncResponse
from app.services.drive import GoogleDriveUploadService, get_drive_upload_service
from app.services.drive.base import PhotoUploadItem, VisitMetadata
from app.services.drive.naming import build_drive_filename

router = APIRouter(prefix="/visits", tags=["visits"])


@router.post("/{visit_id}/sync", response_model=VisitSyncResponse)
def sync_visit(
    visit_id: str,
    visit_metadata: str = Form(
        ..., description="JSON-encoded VisitSyncMetadata for this visit."
    ),
    photos_metadata: str = Form(
        ...,
        description="JSON-encoded list of PhotoSyncMetadata, one per uploaded file, "
        "matched to `files` by position.",
    ),
    files: list[UploadFile] = File(
        ..., description="The 5 watermarked photo files, in the same order as photos_metadata."
    ),
    drive_service: GoogleDriveUploadService = Depends(get_drive_upload_service),
    current_employee: Employee = Depends(get_current_employee),
) -> VisitSyncResponse:
    """Uploads a PM visit's watermarked photos to Google Drive.

    Requires a logged-in employee (see app/api/deps.py). The uploaded
    `employee_id` metadata always comes from the verified JWT
    (`current_employee.employee_code`), never from `visit_metadata` in
    the request body — the Flutter app still sends its own
    `employee_id` there (unchanged wire format), but it is ignored for
    this purpose rather than trusted.

    This is the backend upload interface the Flutter app's
    GoogleDriveUploadService calls — Google credentials live only on
    this server; the app never talks to Google Drive directly. See
    backend/README.md ("Google Drive Upload") and
    docs/data-model.md for the folder structure, metadata, and
    idempotency/retry behavior.

    A non-"synced" response (or a non-200 status) means the Flutter
    app's SyncManager marks the visit SYNC_FAILED and retries later;
    nothing here deletes or requires deleting any local data.
    """
    try:
        visit_data = VisitSyncMetadata.model_validate_json(visit_metadata)
    except ValueError as exc:
        return VisitSyncResponse(status="failed", message=f"Invalid visit_metadata: {exc}")

    if visit_data.visit_id != visit_id:
        return VisitSyncResponse(
            status="failed",
            message="visit_id in the URL path does not match visit_metadata.visit_id.",
        )

    try:
        raw_photos_metadata = json.loads(photos_metadata)
        photos_data = [PhotoSyncMetadata.model_validate(item) for item in raw_photos_metadata]
    except ValueError as exc:
        return VisitSyncResponse(status="failed", message=f"Invalid photos_metadata: {exc}")

    if len(photos_data) != len(files):
        return VisitSyncResponse(
            status="failed",
            message=(
                f"photos_metadata has {len(photos_data)} entries but {len(files)} files "
                "were uploaded; they must match 1:1 by position."
            ),
        )

    visit = VisitMetadata(
        visit_id=visit_data.visit_id,
        employee_id=current_employee.employee_code,
        pop_id=visit_data.pop_id,
        pop_code=visit_data.pop_code,
        district=visit_data.district,
        block=visit_data.block,
        gp=visit_data.gp,
        visit_date=visit_data.visit_date,
    )

    photo_items: list[PhotoUploadItem] = []
    for meta, upload in zip(photos_data, files, strict=True):
        try:
            captured_at = datetime.fromisoformat(meta.captured_at)
        except ValueError as exc:
            return VisitSyncResponse(
                status="failed", message=f"Invalid captured_at for {meta.category}: {exc}"
            )
        content = upload.file.read()
        filename = build_drive_filename(visit.pop_code, meta.category, captured_at)
        photo_items.append(
            PhotoUploadItem(
                category=meta.category,
                captured_at=meta.captured_at,
                latitude=meta.latitude,
                longitude=meta.longitude,
                accuracy_m=meta.accuracy_m,
                filename=filename,
                content=content,
            )
        )

    try:
        results = drive_service.upload_visit_photos(visit, photo_items)
    except Exception as exc:  # noqa: BLE001 - any Drive failure must become a clean "failed" response
        return VisitSyncResponse(status="failed", message=str(exc))

    return VisitSyncResponse(
        status="synced",
        photos=[
            PhotoSyncResult(
                category=result.category,
                drive_file_id=result.drive_file_id,
                drive_file_link=result.drive_file_link,
                duplicate=result.duplicate,
            )
            for result in results
        ],
    )
