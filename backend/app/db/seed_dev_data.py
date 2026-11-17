from sqlalchemy.orm import Session

from app.models.block import Block
from app.models.district import District
from app.models.employee import Employee
from app.models.grama_panchayat import GramaPanchayat
from app.models.pop import Pop

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

# District → Block → GP → { pop_code: (name, is_active) }.
# Deliberately no latitude/longitude/geofence data: the official POP
# coordinate master has not been supplied yet (see docs/data-model.md).
# One POP is seeded inactive to exercise the Active/Inactive status field.
_DEV_LOCATION_HIERARCHY = {
    "Chennai": {
        "Sholinganallur": {
            "Semmancheri GP": {
                "POP-CHN-001": ("Semmancheri POP 1", True),
                "POP-CHN-002": ("Semmancheri POP 2", False),
            },
            "Kazhipattur GP": {
                "POP-CHN-003": ("Kazhipattur POP 1", True),
            },
        },
        "Tambaram": {
            "Chitlapakkam GP": {
                "POP-CHN-004": ("Chitlapakkam POP 1", True),
            },
        },
    },
    "Madurai": {
        "Thiruparankundram": {
            "Avaniyapuram GP": {
                "POP-MDU-001": ("Avaniyapuram POP 1", True),
            },
        },
    },
}


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


def seed_dev_locations(db: Session) -> None:
    """Insert a small District → Block → GP → POP hierarchy for local/dev
    testing, so the POP selection screen has data to show immediately.

    No latitude/longitude/geofence data is created — see
    app/models/pop.py. No-op if any District already exists.
    """
    if db.query(District).first() is not None:
        return

    for district_name, blocks in _DEV_LOCATION_HIERARCHY.items():
        district = District(name=district_name)
        db.add(district)
        db.flush()

        for block_name, gps in blocks.items():
            block = Block(district_id=district.id, name=block_name)
            db.add(block)
            db.flush()

            for gp_name, pops in gps.items():
                gp = GramaPanchayat(block_id=block.id, name=gp_name)
                db.add(gp)
                db.flush()

                for pop_code, (pop_name, is_active) in pops.items():
                    db.add(
                        Pop(
                            gp_id=gp.id,
                            pop_code=pop_code,
                            name=pop_name,
                            is_active=is_active,
                        )
                    )
    db.commit()
