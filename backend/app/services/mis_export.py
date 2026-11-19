import csv
import io
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from openpyxl import Workbook
from sqlalchemy.orm import Session

from app.models.block import Block
from app.models.district import District
from app.models.employee import Employee
from app.models.grama_panchayat import GramaPanchayat
from app.models.pm_photo import MANDATORY_PHOTO_CATEGORIES
from app.models.pm_visit import PmVisit
from app.models.pop import Pop
from app.services.compliance import category_breakdown, is_compliant

COLUMNS = [
    "Visit ID",
    "Visit Date",
    "Employee ID",
    "Employee Name",
    "District",
    "Block",
    "GP",
    "POP Code",
    "POP Name",
    "Visit Status",
    "Categories Present",
    "Categories Missing",
    "Overall Compliance",
    "Sync Status",
    "First Synced At",
    "Last Synced At",
]


@dataclass
class MisRow:
    """One line of the monthly MIS export - either a real synced visit,
    or a placeholder "Pending" line for an active POP that received
    none in the reporting month. Every field here is either read
    directly from PmVisit/PmPhoto/Employee/Pop/GramaPanchayat/Block/
    District, or derived the same way the Dashboard already does
    (is_compliant/category_breakdown, see app/services/compliance.py)
    - nothing here is invented or assumed.
    """

    visit_id: str | None
    visit_date: str | None
    employee_id: str | None
    employee_name: str | None
    district_name: str
    block_name: str
    gp_name: str
    pop_code: str
    pop_name: str | None
    visit_status: str  # "Completed" | "Pending"
    categories_present: str
    categories_missing: str
    overall_compliance: str  # "Compliant" | "Incomplete" | "" (Pending rows)
    sync_status: str  # "Synced" | "Not Synced" - see module docstring note below
    first_synced_at: str | None
    last_synced_at: str | None

    def as_list(self) -> list[str]:
        return [
            self.visit_id or "",
            self.visit_date or "",
            self.employee_id or "",
            self.employee_name or "",
            self.district_name,
            self.block_name,
            self.gp_name,
            self.pop_code,
            self.pop_name or "",
            self.visit_status,
            self.categories_present,
            self.categories_missing,
            self.overall_compliance,
            self.sync_status,
            self.first_synced_at or "",
            self.last_synced_at or "",
        ]


def month_bounds(year: int, month: int) -> tuple[date, date]:
    """First and last calendar day of (year, month) - the monthly MIS
    reporting period. This is a different, independently documented
    granularity from the Dashboard's fortnight
    (app/services/compliance.py:fortnight_bounds): the project has
    always distinguished fortnightly *compliance* checks from a
    monthly *MIS* report (see docs/data-model.md), so this is not a
    new or conflicting period rule - just the other one, finally
    implemented.
    """
    start = date(year, month, 1)
    if month == 12:
        end = date(year, 12, 31)
    else:
        end = date(year, month + 1, 1) - timedelta(days=1)
    return start, end


def _parse_visit_date(value: str) -> date:
    return datetime.strptime(value, "%Y-%m-%d").date()


def build_mis_rows(
    db: Session,
    start: date,
    end: date,
    *,
    district_id: int | None = None,
    block_id: int | None = None,
    gp_id: int | None = None,
    pop_id: int | None = None,
    employee_code: str | None = None,
) -> list[MisRow]:
    """One row per successfully synced PmVisit in [start, end] that
    matches the given geographic/employee filters, plus one "Pending"
    row for every active POP (matching the geographic filters only)
    that received none in that window - mirroring the Dashboard's
    completed/pending concept at monthly instead of fortnightly grain.

    "Sync Status" currently always mirrors "Visit Status" (Synced for
    every real row, Not Synced for every Pending row): the backend
    only ever persists a PmVisit after its Google Drive upload has
    already succeeded (see app/services/pm_visits.py), so there is no
    backend-visible intermediate/failed/offline sync state to report
    separately - those exist only on the mobile device (see
    docs/data-model.md, "Completed vs pending"). This column is kept
    distinct from Visit Status because it was explicitly requested,
    not because the data currently supports a richer value.

    Pending rows are omitted when `employee_code` is set: "no visit
    from employee X at POP Y" is not the same claim as "POP Y was not
    visited by anyone", so an employee-scoped export reports only that
    employee's actual visits.
    """
    pop_query = (
        db.query(Pop)
        .join(GramaPanchayat, Pop.gp_id == GramaPanchayat.id)
        .join(Block, GramaPanchayat.block_id == Block.id)
        .join(District, Block.district_id == District.id)
        .filter(Pop.is_active.is_(True))
    )
    if district_id is not None:
        pop_query = pop_query.filter(District.id == district_id)
    if block_id is not None:
        pop_query = pop_query.filter(Block.id == block_id)
    if gp_id is not None:
        pop_query = pop_query.filter(GramaPanchayat.id == gp_id)
    if pop_id is not None:
        pop_query = pop_query.filter(Pop.id == pop_id)
    matching_pops: dict[int, Pop] = {pop.id: pop for pop in pop_query.all()}

    employee_filter_id: int | None = None
    if employee_code is not None:
        employee = db.query(Employee).filter(Employee.employee_code == employee_code).one_or_none()
        employee_filter_id = employee.id if employee else -1  # no match -> no rows, not an error

    rows: list[MisRow] = []
    visited_pop_ids: set[int] = set()

    if matching_pops:
        candidate_visits = (
            db.query(PmVisit).filter(PmVisit.pop_id.in_(matching_pops.keys())).all()
        )
    else:
        candidate_visits = []

    for visit in candidate_visits:
        if employee_filter_id is not None and visit.employee_id != employee_filter_id:
            continue
        visit_date = _parse_visit_date(visit.visit_date)
        if not (start <= visit_date <= end):
            continue

        pop = matching_pops[visit.pop_id]
        present, missing = category_breakdown(visit)
        visited_pop_ids.add(visit.pop_id)

        rows.append(
            MisRow(
                visit_id=visit.id,
                visit_date=visit.visit_date,
                employee_id=visit.employee.employee_code,
                employee_name=visit.employee.name,
                district_name=pop.gp.block.district.name,
                block_name=pop.gp.block.name,
                gp_name=pop.gp.name,
                pop_code=pop.pop_code,
                pop_name=pop.name,
                visit_status="Completed",
                categories_present=", ".join(present),
                categories_missing=", ".join(missing),
                overall_compliance="Compliant" if is_compliant(visit) else "Incomplete",
                sync_status="Synced",
                first_synced_at=visit.first_synced_at.isoformat(),
                last_synced_at=visit.last_synced_at.isoformat(),
            )
        )

    if employee_filter_id is None:
        for pop_id_, pop in matching_pops.items():
            if pop_id_ in visited_pop_ids:
                continue
            rows.append(
                MisRow(
                    visit_id=None,
                    visit_date=None,
                    employee_id=None,
                    employee_name=None,
                    district_name=pop.gp.block.district.name,
                    block_name=pop.gp.block.name,
                    gp_name=pop.gp.name,
                    pop_code=pop.pop_code,
                    pop_name=pop.name,
                    visit_status="Pending",
                    categories_present="",
                    categories_missing=", ".join(sorted(MANDATORY_PHOTO_CATEGORIES)),
                    overall_compliance="",
                    sync_status="Not Synced",
                    first_synced_at=None,
                    last_synced_at=None,
                )
            )

    rows.sort(
        key=lambda r: (r.district_name, r.block_name, r.gp_name, r.pop_code, r.visit_date or "")
    )
    return rows


def rows_to_csv(rows: list[MisRow]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(COLUMNS)
    for row in rows:
        writer.writerow(row.as_list())
    return buffer.getvalue()


def rows_to_xlsx(rows: list[MisRow]) -> bytes:
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "MIS Export"
    sheet.append(COLUMNS)
    for row in rows:
        sheet.append(row.as_list())
    buffer = io.BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()
