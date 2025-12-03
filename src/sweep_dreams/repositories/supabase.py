"""Supabase repository implementation for schedule data."""

from typing import Any

import requests
from pydantic import BaseModel

from sweep_dreams.domain.models import SweepingSchedule
from sweep_dreams.repositories.exceptions import (
    ScheduleNotFoundError,
    RepositoryConnectionError,
    RepositoryAuthenticationError,
)


class SupabaseSettings(BaseModel):
    """Settings for Supabase connection."""

    url: str
    key: str
    table: str = "schedules"
    rpc_function: str = "schedules_near"

    @property
    def rest_endpoint(self) -> str:
        return f"{self.url.rstrip('/')}/rest/v1/{self.table}"

    @property
    def rpc_endpoint(self) -> str:
        return f"{self.url.rstrip('/')}/rest/v1/rpc/{self.rpc_function}"


class SupabaseScheduleRepository:
    """Repository for accessing schedule data from Supabase."""

    def __init__(self, settings: SupabaseSettings):
        self.settings = settings
        self.session = requests.Session()
        self.session.headers.update(
            {
                "apikey": settings.key,
                "Authorization": f"Bearer {settings.key}",
                "Accept": "application/json",
            }
        )

    def closest_schedules(
        self, *, latitude: float, longitude: float
    ) -> list[SweepingSchedule]:
        """
        Fetch the closest schedules to the given coordinates.

        Args:
            latitude: Latitude coordinate
            longitude: Longitude coordinate

        Returns:
            List of SweepingSchedule objects

        Raises:
            RepositoryConnectionError: If unable to connect to Supabase
            RepositoryAuthenticationError: If authentication fails
            ScheduleNotFoundError: If no schedules found near location
        """
        body = {"lon": longitude, "lat": latitude}
        try:
            response = self.session.post(
                self.settings.rpc_endpoint, json=body, timeout=(5, 10)
            )
        except requests.exceptions.RequestException as exc:
            raise RepositoryConnectionError(
                "Unable to connect to schedule database"
            ) from exc

        if response.status_code in {401, 403}:
            raise RepositoryAuthenticationError("Database authentication failed")
        if response.status_code >= 500:
            raise RepositoryConnectionError("Database query failed")
        if not response.ok:
            raise RepositoryConnectionError(f"Database error: {response.text}")

        payload: list[dict[str, Any]] = response.json()
        if not payload:
            raise ScheduleNotFoundError("No schedule found near location")

        valid_payload = [SweepingSchedule.model_validate(item) for item in payload]

        return valid_payload

    def get_schedule_by_block_sweep_id(self, block_sweep_id: int) -> SweepingSchedule:
        """Fetch a single schedule by its block_sweep_id."""
        params = {
            "block_sweep_id": f"eq.{block_sweep_id}",
            "limit": 1,
        }
        try:
            response = self.session.get(
                self.settings.rest_endpoint, params=params, timeout=(5, 10)
            )
        except requests.exceptions.RequestException as exc:
            raise RepositoryConnectionError(
                "Unable to connect to schedule database"
            ) from exc

        if response.status_code in {401, 403}:
            raise RepositoryAuthenticationError("Database authentication failed")
        if response.status_code >= 500:
            raise RepositoryConnectionError("Database query failed")
        if not response.ok:
            raise RepositoryConnectionError(f"Database error: {response.text}")

        payload: list[dict[str, Any]] = response.json()
        if not payload:
            raise ScheduleNotFoundError("Schedule not found for block_sweep_id")

        return SweepingSchedule.model_validate(payload[0])
