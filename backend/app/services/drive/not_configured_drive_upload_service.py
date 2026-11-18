from app.services.drive.base import (
    GoogleDriveUploadService,
    PhotoUploadItem,
    PhotoUploadResult,
    VisitMetadata,
)


class NotConfiguredDriveUploadService(GoogleDriveUploadService):
    """Used when no Google service account is configured on this server
    (`settings.google_service_account_file` is unset). Mirrors the
    Flutter app's own `NotImplementedDriveUploadService`: every call
    fails clearly rather than silently pretending to succeed, so the
    `/visits/{id}/sync` endpoint — and the sync queue/retry logic that
    calls it — can be exercised in development without real Google
    credentials.
    """

    def upload_visit_photos(
        self, visit: VisitMetadata, photos: list[PhotoUploadItem]
    ) -> list[PhotoUploadResult]:
        raise RuntimeError(
            "Google Drive is not configured on this server. Set "
            "GOOGLE_SERVICE_ACCOUNT_FILE to a valid service-account key "
            "file path to enable uploads."
        )
