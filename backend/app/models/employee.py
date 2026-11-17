from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Employee(Base):
    """A field engineer / app user.

    assigned_district_name is a plain string for now rather than a FK to
    a District table, since the District/Block/GP/POP hierarchy has not
    been implemented yet (see docs/data-model.md). It will be replaced by
    assigned_district_id once that module exists.
    """

    __tablename__ = "employees"

    id: Mapped[int] = mapped_column(primary_key=True)
    employee_code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(128))
    mobile_number: Mapped[str] = mapped_column(String(15))
    assigned_district_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
