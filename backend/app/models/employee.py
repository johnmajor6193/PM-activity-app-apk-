from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Employee(Base):
    """A field engineer / app user.

    assigned_district_name is a plain string rather than a FK to the
    District table: Employee Login was deliberately kept unchanged
    while the District/Block/GP/POP hierarchy was built afterward (see
    docs/data-model.md). Linking it to a real district_id FK remains a
    future step, not yet scheduled.
    """

    __tablename__ = "employees"

    id: Mapped[int] = mapped_column(primary_key=True)
    employee_code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(128))
    mobile_number: Mapped[str] = mapped_column(String(15))
    assigned_district_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
