from abc import ABC, abstractmethod

from sqlalchemy.orm import Session

from app.models.employee import Employee


class AuthStrategy(ABC):
    """Common interface for employee login.

    The login endpoint depends only on this interface, so the active
    strategy can be swapped via settings.auth_mode (see
    app/services/auth/__init__.py:get_auth_strategy) without touching the
    endpoint or schemas. DevLoginStrategy is the current implementation;
    an OTP-based strategy is planned to replace it for production.
    """

    @abstractmethod
    def authenticate(self, db: Session, employee_code: str, mobile_number: str) -> Employee:
        """Return the matching, active Employee or raise AuthenticationError."""
