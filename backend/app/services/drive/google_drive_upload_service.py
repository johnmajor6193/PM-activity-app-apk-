import io

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload

from app.core.config import settings
from app.services.drive.base import (
    GoogleDriveUploadService,
    PhotoUploadItem,
    PhotoUploadResult,
    VisitMetadata,
)
from app.services.drive.naming import build_drive_folder_segments

_SCOPES = ["https://www.googleapis.com/auth/drive"]
_FOLDER_MIME_TYPE = "application/vnd.google-apps.folder"


def _escape(value: str) -> str:
    """Escapes a value for safe interpolation into a Drive API `q` query."""
    return value.replace("\\", "\\\\").replace("'", "\\'")


class GoogleDriveServiceAccountUploadService(GoogleDriveUploadService):
    """Real implementation: authenticates with a Google service account
    and uploads via the Drive v3 API.

    Requires `settings.google_service_account_file` to point at a valid
    service-account JSON key file readable by the server process. That
    file is never part of this repository — see backend/README.md
    ("Google Drive configuration") for how to obtain and configure one.
    """

    def __init__(self) -> None:
        if not settings.google_service_account_file:
            raise RuntimeError(
                "GOOGLE_SERVICE_ACCOUNT_FILE is not set; cannot create a "
                "GoogleDriveServiceAccountUploadService."
            )
        credentials = service_account.Credentials.from_service_account_file(
            settings.google_service_account_file, scopes=_SCOPES
        )
        self._drive = build("drive", "v3", credentials=credentials, cache_discovery=False)

    def upload_visit_photos(
        self, visit: VisitMetadata, photos: list[PhotoUploadItem]
    ) -> list[PhotoUploadResult]:
        folder_id = self._ensure_folder_path(visit)
        return [self._upload_one(folder_id, visit, photo) for photo in photos]

    def _ensure_folder_path(self, visit: VisitMetadata) -> str:
        segments = build_drive_folder_segments(visit, settings.google_drive_root_folder_name)
        parent_id = settings.google_drive_parent_folder_id
        for segment in segments:
            parent_id = self._ensure_folder(segment, parent_id)
        return parent_id

    def _ensure_folder(self, name: str, parent_id: str | None) -> str:
        """Finds an existing folder named `name` under `parent_id`, or
        creates one. This is what makes repeated syncs of the same
        visit idempotent at the folder level, not just the file level.
        """
        query = f"name = '{_escape(name)}' and mimeType = '{_FOLDER_MIME_TYPE}' and trashed = false"
        query += f" and '{parent_id}' in parents" if parent_id else " and 'root' in parents"

        existing = (
            self._drive.files()
            .list(q=query, fields="files(id)", spaces="drive", supportsAllDrives=True)
            .execute()
        )
        files = existing.get("files", [])
        if files:
            return files[0]["id"]

        metadata: dict[str, object] = {"name": name, "mimeType": _FOLDER_MIME_TYPE}
        if parent_id:
            metadata["parents"] = [parent_id]
        created = (
            self._drive.files()
            .create(body=metadata, fields="id", supportsAllDrives=True)
            .execute()
        )
        return created["id"]

    def _upload_one(
        self, folder_id: str, visit: VisitMetadata, photo: PhotoUploadItem
    ) -> PhotoUploadResult:
        # Idempotency: if a file with this exact deterministic name
        # already exists in this visit's folder, reuse it instead of
        # creating a duplicate (e.g. on a retried sync after a network
        # failure that happened after the first upload succeeded).
        query = (
            f"name = '{_escape(photo.filename)}' and '{folder_id}' in parents and trashed = false"
        )
        existing = (
            self._drive.files()
            .list(q=query, fields="files(id, webViewLink)", spaces="drive", supportsAllDrives=True)
            .execute()
        )
        files = existing.get("files", [])
        if files:
            return PhotoUploadResult(
                category=photo.category,
                drive_file_id=files[0]["id"],
                drive_file_link=files[0].get("webViewLink", ""),
                duplicate=True,
            )

        metadata = {
            "name": photo.filename,
            "parents": [folder_id],
            # Custom metadata attached to the file itself (requirement:
            # upload metadata along with each photo where practical).
            "appProperties": {
                "visit_id": visit.visit_id,
                "employee_id": visit.employee_id,
                "pop_id": str(visit.pop_id),
                "district": visit.district,
                "block": visit.block,
                "gp": visit.gp,
                "category": photo.category,
                "captured_at": photo.captured_at,
                "latitude": str(photo.latitude),
                "longitude": str(photo.longitude),
                "accuracy_m": str(photo.accuracy_m),
            },
        }
        media = MediaIoBaseUpload(io.BytesIO(photo.content), mimetype="image/jpeg", resumable=False)
        created = (
            self._drive.files()
            .create(body=metadata, media_body=media, fields="id, webViewLink", supportsAllDrives=True)
            .execute()
        )
        return PhotoUploadResult(
            category=photo.category,
            drive_file_id=created["id"],
            drive_file_link=created.get("webViewLink", ""),
            duplicate=False,
        )
