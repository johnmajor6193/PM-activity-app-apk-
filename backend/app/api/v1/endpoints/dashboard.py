from fastapi import APIRouter

# District-wise / engineer-wise / POP-wise dashboards and MIS export are
# implemented in a later development step.
router = APIRouter(prefix="/dashboard", tags=["dashboard"])
