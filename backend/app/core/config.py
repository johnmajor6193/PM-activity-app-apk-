from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration, loaded from environment variables / .env.

    Only the fields needed to stand the scaffold up are defined here.
    Auth, Google Drive, and other settings are added in later steps.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "TANFINET POP PM Monitoring API"
    database_url: str = "postgresql://postgres:postgres@localhost:5432/tanfinet_pm"


settings = Settings()
