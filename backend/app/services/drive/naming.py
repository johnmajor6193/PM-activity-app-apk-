import re
from datetime import datetime

from app.services.drive.base import VisitMetadata

_UNSAFE_CHARS = re.compile(r"[^A-Za-z0-9_-]+")


def build_drive_folder_segments(visit: VisitMetadata, root_folder_name: str) -> list[str]:
    """The Drive folder path for a visit, as a list of segment names to
    create/find in order:

        <root>/<District>/<Block>/<GP>/<POP code>/PM Visits/<date>/<visit id>
    """
    return [
        root_folder_name,
        visit.district,
        visit.block,
        visit.gp,
        visit.pop_code,
        "PM Visits",
        visit.visit_date,
        visit.visit_id,
    ]


def build_drive_filename(pop_code: str, category: str, captured_at: datetime) -> str:
    """Deterministic, human-readable, filesystem/Drive-safe file name.

    e.g. build_drive_filename("POP-00125", "pop_rack", <2026-11-17 17:25:42>)
         -> "POP-00125_POP-RACK_2026-11-17_172542.jpg"
    """
    safe_pop_code = _UNSAFE_CHARS.sub("-", pop_code)
    category_slug = category.upper().replace("_", "-")
    date_part = captured_at.strftime("%Y-%m-%d")
    time_part = captured_at.strftime("%H%M%S")
    return f"{safe_pop_code}_{category_slug}_{date_part}_{time_part}.jpg"
