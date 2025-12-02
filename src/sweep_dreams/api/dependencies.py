"""FastAPI dependency injection setup."""

from functools import lru_cache

from fastapi import HTTPException

from sweep_dreams.config.settings import get_settings
from sweep_dreams.repositories.supabase import SupabaseScheduleRepository, SupabaseSettings


@lru_cache(maxsize=1)
def get_schedule_repository() -> SupabaseScheduleRepository:
    """Get the schedule repository instance (cached)."""
    settings = get_settings()
    supabase_settings = SupabaseSettings(
        url=settings.database.url,
        key=settings.database.key,
        table=settings.database.table,
        rpc_function=settings.database.rpc_function,
    )
    return SupabaseScheduleRepository(supabase_settings)


def repository_dependency() -> SupabaseScheduleRepository:
    """FastAPI dependency for repository injection."""
    try:
        return get_schedule_repository()
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=f"Repository initialization failed: {exc}") from exc
