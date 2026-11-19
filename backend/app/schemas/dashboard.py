from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel


class PopPeriodStatusOut(BaseModel):
    """One active POP's status for a single fortnight.

    `status` is `"completed"` if the POP received *any* successfully
    synced visit in the period, `"pending"` if it received none - this
    is independent of `is_compliant` (5/5 mandatory categories), which
    is only meaningful when `status == "completed"` (it is always
    `False` when pending, since there is no visit to be compliant).

    `"pending"` here means only "no synced visit yet this period" - it
    cannot say whether an engineer is currently out at this POP, has
    not started, or had a sync fail, since the mobile app never
    transmits those in-progress states to the backend (see
    docs/data-model.md and app/services/compliance.py).
    """

    pop_id: int
    pop_code: str
    pop_name: str | None
    status: Literal["completed", "pending"]
    is_compliant: bool
    latest_visit_id: str | None
    categories_present: list[str]
    categories_missing: list[str]


class DistrictComplianceOut(BaseModel):
    district_id: int
    district_name: str
    total_active_pops: int
    compliant_pops: int
    compliance_percent: float
    completed_pops: int
    pending_pops: int
    pops: list[PopPeriodStatusOut]


class DistrictDashboardResponse(BaseModel):
    period_start: date
    period_end: date
    districts: list[DistrictComplianceOut]


class EngineerComplianceOut(BaseModel):
    employee_id: str
    name: str
    visits_synced: int
    compliant_visits: int


class EngineerDashboardResponse(BaseModel):
    period_start: date
    period_end: date
    engineers: list[EngineerComplianceOut]


class PopVisitOut(BaseModel):
    visit_id: str
    employee_id: str
    employee_name: str
    visit_date: str
    status: Literal["completed"]
    photo_count: int
    is_compliant: bool
    categories_present: list[str]
    categories_missing: list[str]
    first_synced_at: datetime
    last_synced_at: datetime
