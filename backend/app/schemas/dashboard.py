from datetime import date, datetime

from pydantic import BaseModel


class DistrictComplianceOut(BaseModel):
    district_id: int
    district_name: str
    total_active_pops: int
    compliant_pops: int
    compliance_percent: float


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
    photo_count: int
    is_compliant: bool
    first_synced_at: datetime
    last_synced_at: datetime
