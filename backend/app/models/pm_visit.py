from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class PmVisit(Base):
    """A PM visit the backend knows was successfully synced to Google
    Drive. Written once by app/services/pm_visits.py, from inside
    POST /visits/{visit_id}/sync (see app/api/v1/endpoints/visits.py),
    right after a Drive upload succeeds — never before, so a row here
    always means "this visit's photos are actually on Drive."

    `id` is the client-generated visit id from the mobile app (not a
    backend-assigned UUID) — the same id used in the Drive folder path
    and in the on-device SQLite `pm_visits` table (see
    docs/data-model.md, "PM Visit & PM Photo — Local (On-Device)
    Implementation"). A resync of the same visit (e.g. retried after a
    network failure) updates this row in place rather than duplicating
    it — see record_synced_visit.

    district_name/block_name/gp_name/pop_code are intentionally NOT
    stored here: they are resolved by joining through `pop_id` at query
    time (same pattern as app/api/v1/endpoints/locations.py:get_pop),
    not denormalized, so a dashboard query never reflects a stale
    hierarchy name independently of what POP/locations reports today.

    There is deliberately no `within_geofence` field and no visit-level
    check-in GPS: POP master coordinates don't exist, no geofence check
    happens anywhere in this system, and the capture flow only ever
    produces per-photo GPS (see PmPhoto), never a separate visit-level
    reading.
    """

    __tablename__ = "pm_visits"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)
    pop_id: Mapped[int] = mapped_column(ForeignKey("pops.id"), index=True)
    # The visit date the app sent (YYYY-MM-DD, local to the device at
    # capture time) - what fortnight/compliance aggregation buckets by.
    visit_date: Mapped[str] = mapped_column(String(10))
    # When this backend recorded the successful sync - not the same as
    # visit_date, and not editable by re-syncing (see record_synced_visit).
    first_synced_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    last_synced_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    employee: Mapped["Employee"] = relationship()  # noqa: F821
    pop: Mapped["Pop"] = relationship()  # noqa: F821
    photos: Mapped[list["PmPhoto"]] = relationship(  # noqa: F821
        back_populates="visit", cascade="all, delete-orphan"
    )
