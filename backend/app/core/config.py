from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration, loaded from environment variables / .env.

    Only the fields needed to stand the scaffold up are defined here.
    Auth, Google Drive, and other settings are added in later steps.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "TANFINET POP PM Monitoring API"
    # Local development default: a file-based SQLite database, so running
    # the server needs no separate database service installed. PostgreSQL
    # remains fully supported (see app/db/session.py) and is what
    # production should use — set DATABASE_URL to a postgresql:// URL
    # (e.g. postgresql://postgres:postgres@localhost:5432/tanfinet_pm) to
    # use it, including in .env.
    database_url: str = "sqlite:///./tanfinet_pm.db"

    # Auth. "dev" authenticates by Employee ID + mobile number lookup only,
    # for local/test use. Swap to an "otp" strategy in a later step without
    # changing the login endpoint (see app/services/auth/).
    auth_mode: str = "dev"
    secret_key: str = "dev-only-insecure-secret-change-in-production"
    access_token_expire_minutes: int = 480

    # Google Drive upload (see app/services/drive/). Never committed:
    # GOOGLE_SERVICE_ACCOUNT_FILE must point at a service-account JSON
    # key file that exists only on the server (or in its secret store),
    # never in this repository. If unset, the backend falls back to
    # NotConfiguredDriveUploadService, which fails clearly rather than
    # silently pretending to upload.
    google_service_account_file: str | None = None
    # Root folder name under which the District/Block/GP/POP/PM Visits
    # hierarchy is created.
    google_drive_root_folder_name: str = "TANFINET PM Monitoring"
    # Optional: an existing Drive folder (e.g. a Shared Drive folder the
    # service account has been granted access to) to create the root
    # folder under, instead of the service account's own "My Drive".
    # Service accounts typically have no personal storage quota, so a
    # Shared Drive folder is the usual real-world setup.
    google_drive_parent_folder_id: str | None = None


settings = Settings()
