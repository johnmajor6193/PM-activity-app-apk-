from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_employee
from app.db.deps import get_db
from app.models.pop import Pop
from app.schemas.dashboard import (
    DistrictDashboardResponse,
    EngineerDashboardResponse,
    PopVisitOut,
)
from app.services.compliance import (
    district_compliance,
    engineer_compliance,
    fortnight_bounds,
    pop_visit_history,
)

# Every route below requires a logged-in employee, same as /locations
# (see app/api/deps.py) - this is compliance data about employees and
# POPs, not anonymous-readable.
router = APIRouter(
    prefix="/dashboard", tags=["dashboard"], dependencies=[Depends(get_current_employee)]
)


@router.get("/districts", response_model=DistrictDashboardResponse)
def get_district_dashboard(
    for_date: date | None = Query(
        default=None,
        alias="date",
        description="Any date inside the fortnight to report on. Defaults to today.",
    ),
    db: Session = Depends(get_db),
) -> DistrictDashboardResponse:
    """District-wise compliance: for each District, its aggregate
    compliance % (5/5 mandatory categories) plus a per-POP breakdown
    (`pops`) showing each active POP's completed/pending status and
    exactly which mandatory categories are present/missing - see
    docs/data-model.md ("Completed vs pending") for what `pending`
    does and doesn't mean here.
    """
    start, end = fortnight_bounds(for_date or _today())
    rows = district_compliance(db, start, end)
    return DistrictDashboardResponse(period_start=start, period_end=end, districts=rows)


@router.get("/engineers", response_model=EngineerDashboardResponse)
def get_engineer_dashboard(
    for_date: date | None = Query(
        default=None,
        alias="date",
        description="Any date inside the fortnight to report on. Defaults to today.",
    ),
    db: Session = Depends(get_db),
) -> EngineerDashboardResponse:
    """Engineer-wise compliance: for each active Employee, how many
    visits they synced in the fortnight containing `date`, and how
    many of those were fully compliant.
    """
    start, end = fortnight_bounds(for_date or _today())
    rows = engineer_compliance(db, start, end)
    return EngineerDashboardResponse(period_start=start, period_end=end, engineers=rows)


@router.get("/pops/{pop_id}/visits", response_model=list[PopVisitOut])
def get_pop_visit_history(pop_id: int, db: Session = Depends(get_db)) -> list[dict]:
    """POP-wise visit history: every synced visit for this POP, most
    recent first - not windowed to a fortnight, unlike the two
    endpoints above.
    """
    if db.get(Pop, pop_id) is None:
        raise HTTPException(status_code=404, detail="POP not found.")
    return pop_visit_history(db, pop_id)


def _today() -> date:
    # A function (not date.today() inline) so tests can monkeypatch it
    # to pin "today" without depending on the machine's real clock.
    return date.today()
