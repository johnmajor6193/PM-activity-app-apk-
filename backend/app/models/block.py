from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class Block(Base):
    __tablename__ = "blocks"

    id: Mapped[int] = mapped_column(primary_key=True)
    district_id: Mapped[int] = mapped_column(ForeignKey("districts.id"), index=True)
    name: Mapped[str] = mapped_column(String(128))

    district: Mapped["District"] = relationship(back_populates="blocks")  # noqa: F821
    gps: Mapped[list["GramaPanchayat"]] = relationship(back_populates="block")  # noqa: F821
