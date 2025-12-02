"""
API layer - HTTP interface.

This module re-exports key components for backward compatibility.
"""

# Re-export models
from sweep_dreams.api.models import (
    LocationRequest,
    BlockScheduleResponse,
    CheckLocationResponse,
)

# Re-export dependencies
from sweep_dreams.api.dependencies import (
    get_schedule_repository,
    repository_dependency,
)

# Re-export routes
from sweep_dreams.api.routes import (
    check_location,
    check_location_endpoint,
    check_location_api_endpoint,
)

# Re-export app
from sweep_dreams.api.app import create_app, app

# Re-export repository and config for backward compatibility
from sweep_dreams.repositories.supabase import (
    SupabaseScheduleRepository as SupabaseSchedulesClient,
    SupabaseSettings,
)
from sweep_dreams.repositories.exceptions import (
    ScheduleNotFoundError,
    RepositoryConnectionError,
    RepositoryAuthenticationError,
)
from sweep_dreams.config.settings import get_settings

# Re-export from domain for test compatibility (so monkeypatch works)
# Import it here so tests can monkeypatch api.next_sweep_window_from_rule
from sweep_dreams.domain.calendar import next_sweep_window_from_rule

# Backward compatible helpers
from functools import lru_cache

@lru_cache(maxsize=1)
def get_supabase_settings() -> SupabaseSettings:
    """Get Supabase settings (backward compatible wrapper)."""
    app_settings = get_settings()
    return SupabaseSettings(
        url=app_settings.database.url,
        key=app_settings.database.key,
        table=app_settings.database.table,
        rpc_function=app_settings.database.rpc_function,
    )


@lru_cache(maxsize=1)
def get_supabase_client() -> SupabaseSchedulesClient:
    """Get Supabase client (backward compatible wrapper)."""
    return get_schedule_repository()


# Backward compatible alias - point directly to repository_dependency for tests
# This allows test overrides to work correctly
supabase_client_dep = repository_dependency


# For backward compatibility with direct references to _handle_check_location
_handle_check_location = check_location
