from typing import Literal

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.api.deps import get_current_employee
from app.db.deps import get_db
from app.services.mis_export import build_mis_rows, month_bounds, rows_to_csv, rows_to_xlsx

# Protected the same way as /dashboard - this is the same compliance
# data, just exported as a flat monthly file instead of a JSON summary.
router = APIRouter(prefix="/mis", tags=["mis"], dependencies=[Depends(get_current_employee)])

_CSV_MEDIA_TYPE = "text/csv"
_XLSX_MEDIA_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


@router.get("/export")
def export_mis_report(
    year: int = Query(..., ge=2000, le=2100, description="Reporting year, e.g. 2026."),
    month: int = Query(..., ge=1, le=12, description="Reporting month, 1-12."),
    export_format: Literal["csv", "xlsx"] = Query("csv", alias="format"),
    district_id: int | None = None,
    block_id: int | None = None,
    gp_id: int | None = None,
    pop_id: int | None = None,
    employee_id: str | None = Query(
        None, description="Employee ID (employee_code), e.g. ENG001. Suppresses Pending rows."
    ),
    db: Session = Depends(get_db),
) -> Response:
    """Monthly MIS export: one row per successfully synced PM visit in
    the given month, plus one "Pending" row per active POP (within any
    geographic filters given) that received none - see
    app/services/mis_export.py for exactly what each column means and
    the one documented limitation (Sync Status).

    An unmatched filter combination (e.g. an unknown district_id, or
    an employee_id with no visits) returns a report with only the
    header row, not a 404 - several independent optional filters are
    combined here, and "nothing matched" is a normal, valid result.
    """
    start, end = month_bounds(year, month)
    rows = build_mis_rows(
        db,
        start,
        end,
        district_id=district_id,
        block_id=block_id,
        gp_id=gp_id,
        pop_id=pop_id,
        employee_code=employee_id,
    )

    filename = f"mis_export_{year:04d}-{month:02d}.{export_format}"
    if export_format == "xlsx":
        content: bytes = rows_to_xlsx(rows)
        media_type = _XLSX_MEDIA_TYPE
    else:
        # utf-8-sig: a leading BOM so Excel opens a UTF-8 CSV with the
        # right encoding instead of mis-reading non-ASCII characters.
        content = rows_to_csv(rows).encode("utf-8-sig")
        media_type = _CSV_MEDIA_TYPE

    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
