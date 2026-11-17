from sqlalchemy.orm import Session

from app.models.employee import Employee

_DEV_EMPLOYEES = [
    {
        "employee_code": "ENG001",
        "name": "Dev Test Engineer",
        "mobile_number": "9876543210",
        "assigned_district_name": "Chennai",
        "is_active": True,
    },
    {
        "employee_code": "ENG002",
        "name": "Dev Test Engineer Two",
        "mobile_number": "9123456780",
        "assigned_district_name": "Madurai",
        "is_active": True,
    },
]


def seed_dev_employees(db: Session) -> None:
    """Insert a couple of demo employees so the login screen can be tested
    immediately against a fresh database. Only called when auth_mode is
    "dev" (see app/main.py); no-op if any employee already exists.
    """
    if db.query(Employee).first() is not None:
        return
    for data in _DEV_EMPLOYEES:
        db.add(Employee(**data))
    db.commit()
