from sqlalchemy import Float, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

# The 5 mandatory PM visit photo categories (storage-key spelling),
# matching mobile_app's PhotoCategory.storageKey exactly (see
# mobile_app/lib/features/pm_visit/domain/entities/photo_category.dart)
# and the categories already validated in
# backend/tests/test_drive_sync.py. Not a new business rule - this is
# the existing, unchanged set; the dashboard just needs a canonical
# backend-side copy to compute "5/5 categories present" compliance.
MANDATORY_PHOTO_CATEGORIES = frozenset(
    {
        "pop_rack",
        "ups_battery",
        "busbar",
        "earth_pit_chamber",
        "earth_pit_open_with_rod",
    }
)


class PmPhoto(Base):
    """One photo of a successfully synced PmVisit - written alongside
    it by record_synced_visit, from exactly the metadata/Drive result
    POST /visits/{visit_id}/sync already has for that photo. Never
    holds the image bytes or a local file path - those remain
    on-device only; this is Drive-upload metadata, for compliance
    aggregation and traceability, not a copy of the evidence itself.
    """

    __tablename__ = "pm_photos"

    visit_id: Mapped[str] = mapped_column(ForeignKey("pm_visits.id"), primary_key=True)
    category: Mapped[str] = mapped_column(String(32), primary_key=True)
    captured_at: Mapped[str] = mapped_column(String(32))  # ISO 8601, as sent by the app
    gps_lat: Mapped[float] = mapped_column(Float)
    gps_lng: Mapped[float] = mapped_column(Float)
    gps_accuracy_m: Mapped[float] = mapped_column(Float)
    drive_file_id: Mapped[str] = mapped_column(String(255))
    drive_file_link: Mapped[str] = mapped_column(String(1024))

    visit: Mapped["PmVisit"] = relationship(back_populates="photos")  # noqa: F821
