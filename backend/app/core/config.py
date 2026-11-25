"""Application settings. Every value comes from environment variables (no hard-coded configuration)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL


class Settings(BaseSettings):
    """Read from the environment; names are case-insensitive (DB_HOST -> db_host)."""

    model_config = SettingsConfigDict(extra="ignore")

    db_host: str
    db_port: int = 5432
    db_name: str
    db_user: str
    db_password: str

    @property
    def database_url(self) -> URL:
        # URL.create escapes special characters in the password
        return URL.create(
            "postgresql+psycopg",
            username=self.db_user,
            password=self.db_password,
            host=self.db_host,
            port=self.db_port,
            database=self.db_name,
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
