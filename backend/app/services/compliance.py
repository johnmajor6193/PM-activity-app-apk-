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
    return MANDATORY_PHOTO_CATEGORIES.issubset(_present_categories(visit))


def _present_categories(visit: PmVisit) -> set[str]:
    return {photo.category for photo in visit.photos}


def category_breakdown(visit: PmVisit) -> tuple[list[str], list[str]]:
    """Which of the 5 mandatory categories are present vs. missing for
    a synced visit, both sorted for a deterministic API response.
    Derived entirely from the PmPhoto rows already persisted for this
    visit - nothing inferred or assumed.
    """
    present = _present_categories(visit)
    missing = MANDATORY_PHOTO_CATEGORIES - present
    return sorted(present), sorted(missing)


def _best_visit_for_pop(visits: list[PmVisit]) -> PmVisit:
    """When a POP has more than one synced visit in a period, picks
    the one to represent the POP's status: a compliant one if any
    exists, else the most recently started one. Arbitrary but
    deterministic - most periods will only ever have one visit per POP.
    """
    compliant = next((visit for visit in visits if is_compliant(visit)), None)
    if compliant is not None:
        return compliant
    return max(visits, key=lambda visit: (_parse_visit_date(visit.visit_date), visit.first_synced_at))


def district_compliance(db: Session, start: date, end: date) -> list[dict]:
    """One row per District, each with its own POP-by-POP breakdown.

    "Completed" vs "pending" (resolves the audit's completed-vs-pending
    gap) uses only what the backend actually has: a POP is `completed`
    if it has *any* successfully synced PmVisit in [start, end],
    `pending` if it has none. This is **not** the same thing as
    compliant (5/5 categories) - a POP can be `completed` with an
    incomplete photo set; `compliant_pops`/`compliance_percent` below
    are unchanged and still mean 5/5.

    Important limitation, not solved here because the data to solve it
    doesn't exist: `pending` only means "no synced visit yet this
    period." It cannot distinguish an engineer actively capturing this
    POP right now, one who hasn't started, or one whose sync failed
    and is retrying - the mobile app's draft/inProgress/pendingSync/
    syncFailed states are never transmitted to the backend at all (see
    docs/data-model.md). Telling those apart would need the mobile app
    to additionally report a visit-start or sync-attempt event, which
    is a new feature, not a bug in this aggregation - not added here.
    """
    period_visits = _visits_in_period(db, start, end)
    visits_by_pop: dict[int, list[PmVisit]] = {}
    for visit in period_visits:
        visits_by_pop.setdefault(visit.pop_id, []).append(visit)
    compliant_pop_ids = {
        pop_id for pop_id, visits in visits_by_pop.items() if any(is_compliant(v) for v in visits)
    }

    rows: list[dict] = []
    for district in db.query(District).order_by(District.name).all():
        active_pops = (
            db.query(Pop)
            .join(GramaPanchayat, Pop.gp_id == GramaPanchayat.id)
            .join(Block, GramaPanchayat.block_id == Block.id)
            .filter(Block.district_id == district.id, Pop.is_active.is_(True))
            .order_by(Pop.pop_code)
            .all()
        )
        total = len(active_pops)
        compliant = sum(1 for pop in active_pops if pop.id in compliant_pop_ids)

        pop_rows: list[dict] = []
        completed = 0
        for pop in active_pops:
            visits = visits_by_pop.get(pop.id, [])
            if not visits:
                pop_rows.append(
                    {
                        "pop_id": pop.id,
                        "pop_code": pop.pop_code,
                        "pop_name": pop.name,
                        "status": "pending",
                        "is_compliant": False,
                        "latest_visit_id": None,
                        "categories_present": [],
                        "categories_missing": sorted(MANDATORY_PHOTO_CATEGORIES),
                    }
                )
                continue
            completed += 1
            best = _best_visit_for_pop(visits)
            present, missing = category_breakdown(best)
            pop_rows.append(
                {
                    "pop_id": pop.id,
                    "pop_code": pop.pop_code,
                    "pop_name": pop.name,
                    "status": "completed",
                    "is_compliant": is_compliant(best),
                    "latest_visit_id": best.id,
                    "categories_present": present,
                    "categories_missing": missing,
                }
            )

        rows.append(
            {
                "district_id": district.id,
                "district_name": district.name,
                "total_active_pops": total,
                "compliant_pops": compliant,
                "compliance_percent": round((compliant / total) * 100, 1) if total else 0.0,
                "completed_pops": completed,
                "pending_pops": total - completed,
                "pops": pop_rows,
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
    """Every synced visit for one POP, most recent first.

    `status` is always `"completed"` here: a visit only ever appears
    in this list because it was successfully synced (see PmVisit) - a
    `"pending"` POP (see district_compliance) has no visit at all, so
    nothing to list. The field is still included, rather than left
    implicit, so API consumers get an explicit value instead of having
    to infer it from a row's mere presence.
    """
    visits = (
        db.query(PmVisit)
        .filter(PmVisit.pop_id == pop_id)
        .order_by(PmVisit.visit_date.desc(), PmVisit.first_synced_at.desc())
        .all()
    )
    rows = []
    for visit in visits:
        present, missing = category_breakdown(visit)
        rows.append(
            {
                "visit_id": visit.id,
                "employee_id": visit.employee.employee_code,
                "employee_name": visit.employee.name,
                "visit_date": visit.visit_date,
                "status": "completed",
                "photo_count": len(visit.photos),
                "is_compliant": is_compliant(visit),
                "categories_present": present,
                "categories_missing": missing,
                "first_synced_at": visit.first_synced_at,
                "last_synced_at": visit.last_synced_at,
            }
        )
    return rows
