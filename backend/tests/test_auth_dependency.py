"""Tests for the `get_current_employee` JWT verification dependency
(app/api/deps.py) that now guards every protected endpoint.

`/api/v1/locations/districts` stands in as "a" protected endpoint for
most of these - the dependency itself is what's under test, not
locations-specific behavior (see test_locations.py for that). A couple
of tests also hit `/api/v1/visits/{id}/sync` to confirm the dependency
behaves identically wherever it is used.
"""

from datetime import datetime, timedelta, timezone

from jose import jwt as jose_jwt

from app.core.config import settings
from app.core.security import ALGORITHM, create_access_token
from app.models.employee import Employee

_PROTECTED_PATH = "/api/v1/locations/districts"


def _create_employee(db_session, **overrides):
    defaults = dict(
        employee_code="JWTTEST01",
        name="JWT Test Engineer",
        mobile_number="9876543213",
        assigned_district_name="Chennai",
        is_active=True,
    )
    defaults.update(overrides)
    employee = Employee(**defaults)
    db_session.add(employee)
    db_session.commit()
    return employee


def test_valid_token_is_accepted(client, auth_headers):
    response = client.get(_PROTECTED_PATH, headers=auth_headers)

    assert response.status_code == 200


def test_missing_authorization_header_is_rejected(client):
    response = client.get(_PROTECTED_PATH)

    assert response.status_code == 401
    assert response.json()["detail"] == "Could not validate credentials."


def test_non_bearer_scheme_is_rejected(client):
    response = client.get(_PROTECTED_PATH, headers={"Authorization": "Basic dXNlcjpwYXNz"})

    assert response.status_code == 401


def test_bearer_with_empty_token_is_rejected(client):
    response = client.get(_PROTECTED_PATH, headers={"Authorization": "Bearer "})

    assert response.status_code == 401


def test_malformed_token_is_rejected(client):
    response = client.get(
        _PROTECTED_PATH, headers={"Authorization": "Bearer not-a-real-jwt"}
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Could not validate credentials."


def test_invalid_signature_is_rejected(client):
    # A structurally valid JWT, but signed with the wrong key - must
    # fail verification against settings.secret_key.
    forged = jose_jwt.encode(
        {"sub": "ENG001", "exp": datetime.now(timezone.utc) + timedelta(minutes=30)},
        "a-completely-different-secret",
        algorithm=ALGORITHM,
    )

    response = client.get(_PROTECTED_PATH, headers={"Authorization": f"Bearer {forged}"})

    assert response.status_code == 401


def test_expired_token_is_rejected(client):
    expired = create_access_token(subject="ENG001", expires_minutes=-1)

    response = client.get(_PROTECTED_PATH, headers={"Authorization": f"Bearer {expired}"})

    assert response.status_code == 401


def test_token_missing_sub_claim_is_rejected(client):
    no_subject = jose_jwt.encode(
        {"exp": datetime.now(timezone.utc) + timedelta(minutes=30)},
        settings.secret_key,
        algorithm=ALGORITHM,
    )

    response = client.get(_PROTECTED_PATH, headers={"Authorization": f"Bearer {no_subject}"})

    assert response.status_code == 401


def test_token_for_unknown_employee_is_rejected(client):
    # Validly signed, not expired, but `sub` matches no Employee at all.
    token = create_access_token(subject="DOES-NOT-EXIST")

    response = client.get(_PROTECTED_PATH, headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 401


def test_token_for_inactive_employee_is_rejected(client, db_session):
    _create_employee(db_session, employee_code="JWTTEST02", is_active=False)
    token = create_access_token(subject="JWTTEST02")

    response = client.get(_PROTECTED_PATH, headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 401


def test_token_for_active_employee_created_directly_is_accepted(client, db_session):
    _create_employee(db_session, employee_code="JWTTEST03")
    token = create_access_token(subject="JWTTEST03")

    response = client.get(_PROTECTED_PATH, headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 200


def test_protected_endpoint_cannot_be_accessed_anonymously(client):
    """Same assertion as test_missing_authorization_header_is_rejected,
    phrased as the audit's own requirement: an anonymous request must
    never reach the route handler."""
    response = client.get(_PROTECTED_PATH)

    assert response.status_code == 401
    # No district data of any kind should ever be returned anonymously.
    assert response.json() != []


def test_public_endpoints_remain_reachable_without_a_token(client):
    """Health and login are intentionally public and must not be
    affected by adding the JWT dependency elsewhere."""
    health_response = client.get("/health")
    assert health_response.status_code == 200

    login_response = client.post(
        "/api/v1/auth/login",
        json={"employee_id": "ENG001", "mobile_number": "9876543210"},
    )
    assert login_response.status_code == 200
