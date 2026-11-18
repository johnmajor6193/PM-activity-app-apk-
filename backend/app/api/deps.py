from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.db.deps import get_db
from app.models.employee import Employee

# auto_error=False: a missing/malformed Authorization header is handled
# below, as the same 401 as every other verification failure, rather
# than FastAPI's own 403.
_bearer_scheme = HTTPBearer(auto_error=False)

_INVALID_CREDENTIALS_MESSAGE = "Could not validate credentials."
_WWW_AUTHENTICATE_HEADER = {"WWW-Authenticate": "Bearer"}


def _unauthorized() -> HTTPException:
    # Never includes the token or any claim value - only this fixed
    # message, so nothing credential-shaped ever reaches a response
    # body or (via FastAPI's exception handling) a log line.
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=_INVALID_CREDENTIALS_MESSAGE,
        headers=_WWW_AUTHENTICATE_HEADER,
    )


def get_current_employee(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> Employee:
    """FastAPI dependency for every endpoint that requires a logged-in
    employee: verifies the `Authorization: Bearer <token>` header and
    resolves the Employee it identifies.

    Added for the Employee Login module's existing JWT (see
    app/core/security.py) - this does not change how a token is issued,
    only that protected endpoints now actually check one. Rejects with
    401 (request never processed) when any of the following holds,
    without distinguishing which in the response (to avoid confirming
    which part of a forged token was wrong):

    - the Authorization header is missing, or isn't a Bearer token;
    - the JWT is malformed, or its signature doesn't verify;
    - the JWT has expired;
    - its `sub` claim is missing or doesn't match an active Employee.
    """
    if credentials is None or not credentials.credentials:
        raise _unauthorized()

    try:
        payload = decode_access_token(credentials.credentials)
    except JWTError:
        # Covers ExpiredSignatureError and JWTClaimsError too - both
        # are JWTError subclasses - so expiry, a bad signature, and a
        # malformed token are all rejected the same way here.
        raise _unauthorized() from None

    employee_code = payload.get("sub")
    if not employee_code or not isinstance(employee_code, str):
        raise _unauthorized()

    employee = db.query(Employee).filter(Employee.employee_code == employee_code).one_or_none()
    if employee is None or not employee.is_active:
        raise _unauthorized()

    return employee
