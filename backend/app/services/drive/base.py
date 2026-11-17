from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class VisitMetadata:
    """Identifies a PM visit for the purposes of building its Drive
    folder path and attaching metadata to its uploaded photos."""

    visit_id: str
    employee_id: str
    pop_id: int
    pop_code: str
    district: str
    block: str
    gp: str
    visit_date: str  # YYYY-MM-DD, used for the date folder


@dataclass
class PhotoUploadItem:
    """One photo to upload, with the metadata that must travel with it
    (requirement: Visit ID, Employee ID, POP ID, District, Block, GP,
    category, capture timestamp, latitude, longitude, accuracy)."""

    category: str
    captured_at: str  # ISO 8601
    latitude: float
    longitude: float
    accuracy_m: float
    filename: str
    content: bytes


@dataclass
class PhotoUploadResult:
    category: str
    drive_file_id: str
    drive_file_link: str
    # True if an existing file with this name was found in the target
    # folder and reused instead of creating a new one (idempotent retry).
    duplicate: bool


class GoogleDriveUploadService(ABC):
    """Uploads a PM visit's watermarked photos to Google Drive, under
    the District/Block/GP/POP/PM Visits/<date>/<visit id> folder
    convention (see app/services/drive/naming.py).

    This is the abstraction the `/visits/{id}/sync` endpoint depends on
    (via `get_drive_upload_service`, app/services/drive/__init__.py).
    Swapping `GoogleDriveServiceAccountUploadService` (the real
    implementation) for `NotConfiguredDriveUploadService` or
    `FakeDriveUploadService` needs no change to the endpoint.
    """

    @abstractmethod
    def upload_visit_photos(
        self, visit: VisitMetadata, photos: list[PhotoUploadItem]
    ) -> list[PhotoUploadResult]:
        """Uploads every photo, returning one result per photo in the
        same order. Must raise on any failure that should fail the
        whole visit sync — callers must not assume partial success."""
