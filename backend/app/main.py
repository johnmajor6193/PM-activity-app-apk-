from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import models  # noqa: F401  (registers ORM models on Base.metadata)
from app.api.v1.router import api_router
from app.core.config import settings
from app.db.base import Base
from app.db.seed_dev_data import seed_dev_employees
from app.db.session import SessionLocal, engine


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Dev convenience: create tables directly until Alembic migrations
    are introduced in a later step, and seed demo employees in dev mode."""
    Base.metadata.create_all(bind=engine)
    if settings.auth_mode == "dev":
        db = SessionLocal()
        try:
            seed_dev_employees(db)
        finally:
            db.close()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.include_router(api_router, prefix="/api/v1")


@app.get("/health", tags=["health"])
def health_check() -> dict:
    """Basic liveness check used to verify the scaffold runs."""
    return {"status": "ok"}
