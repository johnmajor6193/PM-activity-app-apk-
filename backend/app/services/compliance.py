from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session

from app.models.block import Block
from app.models.district import District
from app.models.employee import Employee
from app.models.grama_panchayat import GramaPanchayat
from app.models.pm_photo import MANDATORY_PHOTO_CATEGORIES
from app.models.pm_visit import PmVisit
from app.models.pop import Pop


def fortnight_bounds(for_date: date) -> tuple[date, date]:
    """The calendar fortnight containing `for_date`: the 1st-15th, or
    the 16th-to-last-day-of-month.

    This is this project's chosen resolution to the previously open
    "fortnight period" decision (see docs/data-model.md, "Open
    Decisions" - calendar-based vs. a rolling 14-day window from first
    visit). Calendar fortnights need no "since when" reference point
    and no per-POP/per-employee state to track, so they were chosen as
    the simpler, deterministic option; revisit if a rolling window
    turns out to be what compliance actually needs.
    """
    if for_date.day <= 15:
        return for_date.replace(day=1), for_date.replace(day=15)

    start = for_date.replace(day=16)
    if for_date.month == 12:
        end = date(for_date.year, 12, 31)
    else:
        end = date(for_date.year, for_date.month + 1, 1) - timedelta(days=1)
    return start, end


def _parse_visit_date(value: str) -> date:
    return datetime.strptime(value, "%Y-%m-%d").date()


def _visits_in_period(db: Session, start: date, end: date) -> list[PmVisit]:
    """Every synced PmVisit whose visit_date falls in [start, end].

    Filtered in Python, not SQL: visit_date is stored as the YYYY-MM-DD
    string the app sent (see PmVisit), and the table is small (one row
    per successfully synced visit) at this project's current scale -
    this keeps the comparison simple and dialect-independent rather
    than relying on SQLite/Postgres string-to-date coercion.
    """
    return [
        visit
        for visit in db.query(PmVisit).all()
        if start <= _parse_visit_date(visit.visit_date) <= end
    ]


def is_compliant(visit: PmVisit) -> bool:
    """True only if every one of the 5 mandatory categories was synced
    for this visit - not just that *a* sync happened. The sync
    endpoint itself does not enforce category completeness (that
    validation lives in the mobile app, see
    PmVisitController.allPhotosValidForSubmission); this checks what
    was actually persisted, not what should have been sent.
    """
    categories = {photo.category for photo in visit.photos}
    return MANDATORY_PHOTO_CATEGORIES.issubset(categories)


def district_compliance(db: Session, start: date, end: date) -> list[dict]:
    """One row per District: how many of its active POPs received at
    least one fully-compliant (5/5 category) visit in [start, end].
    """
    compliant_pop_ids = {
        visit.pop_id for visit in _visits_in_period(db, start, end) if is_compliant(visit)
    }

    rows: list[dict] = []
    for district in db.query(District).order_by(District.name).all():
        active_pops = (
            db.query(Pop)
            .join(GramaPanchayat, Pop.gp_id == GramaPanchayat.id)
            .join(Block, GramaPanchayat.block_id == Block.id)
            .filter(Block.district_id == district.id, Pop.is_active.is_(True))
            .all()
        )
        total = len(active_pops)
        compliant = sum(1 for pop in active_pops if pop.id in compliant_pop_ids)
        rows.append(
            {
                "district_id": district.id,
                "district_name": district.name,
                "total_active_pops": total,
                "compliant_pops": compliant,
                "compliance_percent": round((compliant / total) * 100, 1) if total else 0.0,
            }
        )
    return rows


def engineer_compliance(db: Session, start: date, end: date) -> list[dict]:
    """One row per active Employee: how many visits they synced in
    [start, end], and how many of those were fully compliant (5/5
    categories). Every active employee is listed, including those with
    zero visits in the period - a compliance dashboard needs to show
    who hasn't synced anything too.
    """
    by_employee: dict[int, list[PmVisit]] = {}
    for visit in _visits_in_period(db, start, end):
        by_employee.setdefault(visit.employee_id, []).append(visit)

    rows: list[dict] = []
    for employee in (
        db.query(Employee).filter(Employee.is_active.is_(True)).order_by(Employee.name).all()
    ):
        visits = by_employee.get(employee.id, [])
        rows.append(
            {
                "employee_id": employee.employee_code,
                "name": employee.name,
                "visits_synced": len(visits),
                "compliant_visits": sum(1 for visit in visits if is_compliant(visit)),
            }
        )
    return rows


def pop_visit_history(db: Session, pop_id: int) -> list[dict]:
    """Every synced visit for one POP, most recent first."""
    visits = (
        db.query(PmVisit)
        .filter(PmVisit.pop_id == pop_id)
        .order_by(PmVisit.visit_date.desc(), PmVisit.first_synced_at.desc())
        .all()
    )
    return [
        {
            "visit_id": visit.id,
            "employee_id": visit.employee.employee_code,
            "employee_name": visit.employee.name,
            "visit_date": visit.visit_date,
            "photo_count": len(visit.photos),
            "is_compliant": is_compliant(visit),
            "first_synced_at": visit.first_synced_at,
            "last_synced_at": visit.last_synced_at,
        }
        for visit in visits
    ]
