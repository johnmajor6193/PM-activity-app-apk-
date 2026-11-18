import os
import tempfile

import pytest
from fastapi.testclient import TestClient

# Point the app at an isolated SQLite file instead of the real Postgres
# DATABASE_URL, before anything below imports app.* and reads settings.
_test_db_fd, _test_db_path = tempfile.mkstemp(prefix="tanfinet_pm_test_", suffix=".db")
os.environ["DATABASE_URL"] = f"sqlite:///{_test_db_path}"
os.environ.setdefault("AUTH_MODE", "dev")
os.environ.setdefault("SECRET_KEY", "test-secret-key")


def pytest_sessionfinish(session, exitstatus) -> None:
    os.close(_test_db_fd)
    try:
        os.remove(_test_db_path)
    except OSError:
        pass


@pytest.fixture()
def client():
    from app.main import app

    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def auth_headers(client):
    """A valid `Authorization: Bearer <token>` header for the auto-seeded
    dev employee ENG001 (see app/db/seed_dev_data.py) - for tests that
    need to call a protected endpoint as a legitimately logged-in
    employee."""
    response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "ENG001", "mobile_number": "9876543210"},
    )
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture()
def db_session(client):
    """A DB session on the same test database the app is using. Depends
    on `client` so the startup event (table creation) has already run."""
    from app.db.session import SessionLocal

    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()
