from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class GramaPanchayat(Base):
    """A GP (Grama Panchayat) — third level of the District → Block → GP →
    POP hierarchy."""

    __tablename__ = "grama_panchayats"

    id: Mapped[int] = mapped_column(primary_key=True)
    block_id: Mapped[int] = mapped_column(ForeignKey("blocks.id"), index=True)
    name: Mapped[str] = mapped_column(String(128))

    block: Mapped["Block"] = relationship(back_populates="gps")  # noqa: F821
    pops: Mapped[list["Pop"]] = relationship(back_populates="gp")  # noqa: F821
