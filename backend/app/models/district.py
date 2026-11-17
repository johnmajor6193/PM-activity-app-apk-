from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class District(Base):
    __tablename__ = "districts"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128), unique=True)

    blocks: Mapped[list["Block"]] = relationship(back_populates="district")  # noqa: F821
