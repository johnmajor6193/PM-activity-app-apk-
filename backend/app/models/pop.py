from sqlalchemy import Boolean, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class Pop(Base):
    """A POP (Point of Presence) site.

    Latitude, longitude, and geofence radius are intentionally NOT
    modeled here: the official POP coordinate master data has not been
    supplied yet, and no placeholder/fake coordinates are used. These
    fields, plus POP geofence validation, are added in a later step once
    that data is available — see docs/data-model.md.
    """

    __tablename__ = "pops"

    id: Mapped[int] = mapped_column(primary_key=True)
    gp_id: Mapped[int] = mapped_column(ForeignKey("grama_panchayats.id"), index=True)
    pop_code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    gp: Mapped["GramaPanchayat"] = relationship(back_populates="pops")  # noqa: F821
