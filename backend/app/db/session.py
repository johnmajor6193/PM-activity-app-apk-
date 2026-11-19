from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import settings

# check_same_thread=False only matters for SQLite (the local-dev default,
# and what the test suite uses too); it is ignored by other drivers, so
# this works unchanged for a postgresql:// DATABASE_URL in production.
_connect_args = (
    {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
)
engine = create_engine(settings.database_url, connect_args=_connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
