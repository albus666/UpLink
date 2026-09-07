from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_token: str = Field(min_length=16)
    workspace: Path
    host: str = "0.0.0.0"
    port: int = 8787
    cursor_api_key: str = ""
    agent_bin: str = "agent"
    agent_model: str = "composer-2.5"
    agent_timeout_sec: int = 1800
    max_upload_mb: int = 50
    data_dir: Path = Path("./data")
    cors_origins: str = "*"

    @field_validator("app_token", "cursor_api_key", mode="before")
    @classmethod
    def strip_secret(cls, value: str) -> str:
        return value.strip() if isinstance(value, str) else value

    @field_validator("workspace", "data_dir", mode="before")
    @classmethod
    def expand_path(cls, value: str | Path) -> Path:
        return Path(value).expanduser().resolve()

    @property
    def cors_origin_list(self) -> list[str]:
        raw = [item.strip() for item in self.cors_origins.split(",") if item.strip()]
        return raw or ["*"]

    @property
    def upload_dir(self) -> Path:
        return self.workspace / ".remote-uploads"

    @property
    def db_path(self) -> Path:
        return self.data_dir / "pilot.db"


def load_settings() -> Settings:
    settings = Settings()  # type: ignore[call-arg]
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    settings.workspace.mkdir(parents=True, exist_ok=True)
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    ignore = settings.upload_dir / ".gitignore"
    if not ignore.exists():
        ignore.write_text("*\n!.gitignore\n", encoding="utf-8")
    return settings
