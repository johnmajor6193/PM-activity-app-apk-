import re

from pydantic import BaseModel, field_validator

_MOBILE_NUMBER_PATTERN = re.compile(r"^[6-9]\d{9}$")


class LoginRequest(BaseModel):
    employee_id: str
    mobile_number: str

    @field_validator("employee_id")
    @classmethod
    def employee_id_not_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Employee ID is required.")
        return value

    @field_validator("mobile_number")
    @classmethod
    def mobile_number_valid(cls, value: str) -> str:
        value = value.strip()
        if not _MOBILE_NUMBER_PATTERN.match(value):
            raise ValueError("Enter a valid 10-digit mobile number.")
        return value


class EmployeeProfile(BaseModel):
    employee_id: str
    name: str
    assigned_district: str | None = None


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    employee: EmployeeProfile
