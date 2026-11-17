from pydantic import BaseModel


class VisitSyncMetadata(BaseModel):
    """The `visit_metadata` form field of POST /visits/{visit_id}/sync."""

    visit_id: str
    employee_id: str
    pop_id: int
    pop_code: str
    district: str
    block: str
    gp: str
    visit_date: str  # YYYY-MM-DD


class PhotoSyncMetadata(BaseModel):
    """One entry of the `photos_metadata` form field — matched to the
    uploaded `files` list by position (index i <-> files[i])."""

    category: str
    captured_at: str  # ISO 8601
    latitude: float
    longitude: float
    accuracy_m: float


class PhotoSyncResult(BaseModel):
    category: str
    drive_file_id: str
    drive_file_link: str
    duplicate: bool


class VisitSyncResponse(BaseModel):
    status: str  # "synced" | "failed"
    photos: list[PhotoSyncResult] = []
    message: str | None = None
