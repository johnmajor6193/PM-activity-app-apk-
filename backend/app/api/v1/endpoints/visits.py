from fastapi import APIRouter

# PM visit submission + sync endpoints (visit records, GPS, photo metadata,
# Google Drive links) are implemented in a later development step.
router = APIRouter(prefix="/visits", tags=["visits"])
