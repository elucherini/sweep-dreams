"""Application configuration management."""

import os
from functools import lru_cache

from dotenv import load_dotenv
from pydantic import BaseModel, Field


class DatabaseSettings(BaseModel):
    """Database connection settings."""

    url: str
    key: str
    table: str = "schedules"
    rpc_function: str = "schedules_near"


class CORSSettings(BaseModel):
    """CORS configuration settings."""

    allowed_origins: list[str] = Field(default_factory=lambda: ["*"])

    @staticmethod
    def from_env_string(cors_origins: str = "") -> "CORSSettings":
        """Parse CORS origins from comma-separated environment variable."""
        if not cors_origins or cors_origins == "":
            return CORSSettings()
        origins = [o.strip() for o in cors_origins.split(",")]
        return CORSSettings(allowed_origins=origins)


class AppSettings(BaseModel):
    """Application settings."""

    database: DatabaseSettings
    cors: CORSSettings = Field(default_factory=CORSSettings)


@lru_cache(maxsize=1)
def get_settings() -> AppSettings:
    """
    Get application settings from environment variables.

    Returns:
        AppSettings instance

    Raises:
        RuntimeError: If required environment variables are missing
    """
    load_dotenv()

    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    table = os.getenv("SUPABASE_TABLE", "schedules")
    rpc_function = os.getenv("SUPABASE_RPC_FUNCTION", "schedules_near")
    cors_origins = os.getenv("CORS_ORIGINS", "")

    if not url or not key:
        raise RuntimeError(
            "Supabase credentials are not configured. Set SUPABASE_URL and SUPABASE_KEY environment variables."
        )

    return AppSettings(
        database=DatabaseSettings(
            url=url,
            key=key,
            table=table,
            rpc_function=rpc_function,
        ),
        cors=CORSSettings.from_env_string(cors_origins),
    )
