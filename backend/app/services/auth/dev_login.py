from sqlalchemy.orm import Session

from app.models.employee import Employee
from app.services.auth.base import AuthStrategy
from app.services.auth.errors import AuthenticationError

_INVALID_CREDENTIALS_MESSAGE = "Invalid Employee ID or mobile number."


class DevLoginStrategy(AuthStrategy):
    """Development/test login: matches a pre-registered employee by
    Employee ID + mobile number. No OTP, no password.

    For local/dev and QA use only — not a production authentication
    mechanism. See AuthStrategy for how this is replaced later.
    """

    def authenticate(self, db: Session, employee_code: str, mobile_number: str) -> Employee:
        employee = (
            db.query(Employee)
            .filter(Employee.employee_code == employee_code)
            .one_or_none()
        )
        if employee is None or employee.mobile_number != mobile_number:
            raise AuthenticationError(_INVALID_CREDENTIALS_MESSAGE)
        if not employee.is_active:
            raise AuthenticationError(
                "This employee account is inactive. Contact your administrator.",
                status_code=403,
            )
        return employee
