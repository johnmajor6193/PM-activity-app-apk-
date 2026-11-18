from functools import lru_cache

from app.core.config import settings
from app.services.drive.base import GoogleDriveUploadService
from app.services.drive.google_drive_upload_service import GoogleDriveServiceAccountUploadService
from app.services.drive.not_configured_drive_upload_service import NotConfiguredDriveUploadService

__all__ = ["GoogleDriveUploadService", "get_drive_upload_service"]


@lru_cache
def get_drive_upload_service() -> GoogleDriveUploadService:
    """FastAPI dependency: the active Drive upload implementation.

    Real (GoogleDriveServiceAccountUploadService) when a service
    account file is configured; otherwise NotConfiguredDriveUploadService,
    which fails clearly rather than silently succeeding. Tests override
    this dependency with FakeDriveUploadService — see
    backend/tests/test_drive_sync.py.
    """
    if settings.google_service_account_file:
        return GoogleDriveServiceAccountUploadService()
    return NotConfiguredDriveUploadService()
