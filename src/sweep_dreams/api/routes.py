"""API route handlers."""

from fastapi import Query, Depends, HTTPException

from sweep_dreams.api.dependencies import repository_dependency
from sweep_dreams.api.models import (
    CheckLocationResponse,
    LocationRequest,
    BlockScheduleResponse,
    SubscribeRequest,
    SubscriptionStatus,
)
from sweep_dreams.domain.models import PACIFIC_TZ
from sweep_dreams.domain.calendar import (
    earliest_sweep_window,
)
from sweep_dreams.parsing.converters import sweeping_schedules_to_blocks
from sweep_dreams.repositories.supabase import SupabaseScheduleRepository
from sweep_dreams.repositories.exceptions import (
    ScheduleNotFoundError,
    RepositoryConnectionError,
    RepositoryAuthenticationError,
    SubscriptionNotFoundError,
)
from sweep_dreams.services.subscriptions import SubscriptionService


def check_location(
    latitude: float,
    longitude: float,
    repository: SupabaseScheduleRepository,
) -> CheckLocationResponse:
    """
    Core business logic for checking location schedules.

    Args:
        latitude: Latitude coordinate
        longitude: Longitude coordinate
        repository: Schedule repository instance

    Returns:
        CheckLocationResponse with schedules and next sweep times

    Raises:
        HTTPException: For various error conditions
    """
    # 1. Fetch schedules from repository
    try:
        sweeping_schedules = repository.closest_schedules(
            latitude=latitude, longitude=longitude
        )
    except ScheduleNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RepositoryConnectionError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except RepositoryAuthenticationError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    # 2. Convert to block schedules
    try:
        block_schedules = sweeping_schedules_to_blocks(sweeping_schedules)
    except ValueError as exc:
        raise HTTPException(
            status_code=500, detail=f"Data quality issue: {exc}"
        ) from exc

    # 3. Compute earliest sweep for each block
    schedule_responses = []
    for block_sched in block_schedules:
        try:
            start, end = earliest_sweep_window(block_sched)
        except ValueError as exc:
            raise HTTPException(
                status_code=500, detail=f"Could not compute sweep window: {exc}"
            ) from exc
        schedule_responses.append(BlockScheduleResponse.build(block_sched, start, end))

    return CheckLocationResponse(
        request_point=LocationRequest(latitude=latitude, longitude=longitude),
        schedules=schedule_responses,
        timezone=PACIFIC_TZ.key,
    )


def check_location_endpoint(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    repository: SupabaseScheduleRepository = Depends(repository_dependency),
) -> CheckLocationResponse:
    """GET /check-location endpoint."""
    return check_location(latitude, longitude, repository)


def check_location_api_endpoint(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    repository: SupabaseScheduleRepository = Depends(repository_dependency),
) -> CheckLocationResponse:
    """GET /api/check-location endpoint (backward compatibility)."""
    return check_location(latitude, longitude, repository)


def subscribe_to_schedule(
    request: SubscribeRequest,
    service: SubscriptionService,
) -> SubscriptionStatus:
    """POST /subscriptions endpoint."""
    try:
        return service.subscribe(request)
    except ScheduleNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except SubscriptionNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RepositoryAuthenticationError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except RepositoryConnectionError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def get_subscription_status(
    device_token: str, service: SubscriptionService
) -> SubscriptionStatus:
    """GET /subscriptions/{device_token} endpoint."""
    try:
        return service.get_status(device_token)
    except SubscriptionNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ScheduleNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RepositoryAuthenticationError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except RepositoryConnectionError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def delete_subscription(device_token: str, service: SubscriptionService) -> None:
    """DELETE /subscriptions/{device_token} endpoint."""
    try:
        service.delete(device_token)
    except SubscriptionNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RepositoryAuthenticationError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except RepositoryConnectionError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
