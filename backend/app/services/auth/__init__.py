from app.core.config import settings
from app.services.auth.base import AuthStrategy
from app.services.auth.dev_login import DevLoginStrategy


def get_auth_strategy() -> AuthStrategy:
    """Return the active authentication strategy for settings.auth_mode.

    Add new strategies (e.g. "otp") here as they are implemented; callers
    (the login endpoint) never need to change.
    """
    if settings.auth_mode == "dev":
        return DevLoginStrategy()
    raise NotImplementedError(f"Unsupported auth_mode: {settings.auth_mode!r}")
