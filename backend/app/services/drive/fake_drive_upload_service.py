from app.services.drive.base import (
    GoogleDriveUploadService,
    PhotoUploadItem,
    PhotoUploadResult,
    VisitMetadata,
)


class FakeDriveUploadService(GoogleDriveUploadService):
    """In-memory Drive stand-in for automated tests: no network call,
    no credentials, no real Google Drive involved.

    Tracks uploaded files per (district, block, gp, pop_code,
    visit_date, visit_id) folder key, so calling `upload_visit_photos`
    again with the same visit/photo filenames is idempotent — exactly
    like the real service's existing-file lookup — letting tests verify
    retry/duplicate-prevention behavior without real Drive access.
    """

    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.call_count = 0
        self._uploaded_by_folder: dict[tuple[str, ...], dict[str, dict]] = {}

    def upload_visit_photos(
        self, visit: VisitMetadata, photos: list[PhotoUploadItem]
    ) -> list[PhotoUploadResult]:
        self.call_count += 1
        if self.fail:
            raise RuntimeError("Simulated Google Drive upload failure")

        folder_key = (
            visit.district,
            visit.block,
            visit.gp,
            visit.pop_code,
            visit.visit_date,
            visit.visit_id,
        )
        folder = self._uploaded_by_folder.setdefault(folder_key, {})

        results = []
        for photo in photos:
            existing = folder.get(photo.filename)
            if existing is not None:
                results.append(
                    PhotoUploadResult(
                        category=photo.category,
                        drive_file_id=existing["id"],
                        drive_file_link=existing["link"],
                        duplicate=True,
                    )
                )
                continue

            file_id = f"fake-file-{len(folder) + 1}"
            link = f"https://drive.fake.example/{file_id}"
            folder[photo.filename] = {
                "id": file_id,
                "link": link,
                "content": photo.content,
                "metadata": photo,
            }
            results.append(
                PhotoUploadResult(
                    category=photo.category,
                    drive_file_id=file_id,
                    drive_file_link=link,
                    duplicate=False,
                )
            )
        return results
