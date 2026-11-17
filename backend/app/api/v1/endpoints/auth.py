from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.security import create_access_token
from app.db.deps import get_db
from app.schemas.auth import EmployeeProfile, LoginRequest, LoginResponse
from app.services.auth import get_auth_strategy
from app.services.auth.errors import AuthenticationError

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> LoginResponse:
    """Authenticate an employee and issue an access token + basic profile.

    Delegates the actual check to the configured AuthStrategy (currently
    DevLoginStrategy: Employee ID + mobile number lookup, no OTP) so this
    endpoint does not change when that is replaced later.
    """
    strategy = get_auth_strategy()
    try:
        employee = strategy.authenticate(db, payload.employee_id, payload.mobile_number)
    except AuthenticationError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from exc

    access_token = create_access_token(subject=employee.employee_code)
    return LoginResponse(
        access_token=access_token,
        employee=EmployeeProfile(
            employee_id=employee.employee_code,
            name=employee.name,
            assigned_district=employee.assigned_district_name,
        ),
    )
