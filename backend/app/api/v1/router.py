from fastapi import APIRouter

from app.api.v1.endpoints import auth, dashboard, locations, mis, visits

api_router = APIRouter()

# Routers are wired up now; individual endpoints are added in later steps.
api_router.include_router(auth.router)
api_router.include_router(locations.router)
api_router.include_router(visits.router)
api_router.include_router(dashboard.router)
api_router.include_router(mis.router)
