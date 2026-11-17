from fastapi import APIRouter

# District / Block / GP / POP lookup endpoints are implemented in a later
# development step. See docs/data-model.md for the planned hierarchy.
router = APIRouter(prefix="/locations", tags=["locations"])
