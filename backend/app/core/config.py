from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration, loaded from environment variables / .env.

    Only the fields needed to stand the scaffold up are defined here.
    Auth, Google Drive, and other settings are added in later steps.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "TANFINET POP PM Monitoring API"
    database_url: str = "postgresql://postgres:postgres@localhost:5432/tanfinet_pm"

    # Auth. "dev" authenticates by Employee ID + mobile number lookup only,
    # for local/test use. Swap to an "otp" strategy in a later step without
    # changing the login endpoint (see app/services/auth/).
    auth_mode: str = "dev"
    secret_key: str = "dev-only-insecure-secret-change-in-production"
    access_token_expire_minutes: int = 480


settings = Settings()
