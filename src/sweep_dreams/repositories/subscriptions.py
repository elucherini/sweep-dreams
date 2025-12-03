"""Supabase repository for managing subscriptions."""

from datetime import datetime
from typing import Optional

import requests
from pydantic import BaseModel

from sweep_dreams.repositories.exceptions import (
    RepositoryAuthenticationError,
    RepositoryConnectionError,
    SubscriptionNotFoundError,
)


class SupabaseSubscriptionSettings(BaseModel):
    """Settings for subscriptions table access."""

    url: str
    key: str
    table: str = "subscriptions"

    @property
    def rest_endpoint(self) -> str:
        return f"{self.url.rstrip('/')}/rest/v1/{self.table}"


class SubscriptionRecord(BaseModel):
    """Minimal subscription projection used by services."""

    device_token: str
    platform: str
    schedule_block_sweep_id: int
    lead_minutes: int
    last_notified_at: Optional[datetime] = None

    model_config = {"extra": "ignore"}


class SupabaseSubscriptionRepository:
    """Repository for CRUD operations on subscriptions."""

    def __init__(self, settings: SupabaseSubscriptionSettings):
        self.settings = settings
        self.session = requests.Session()
        self.session.headers.update(
            {
                "apikey": settings.key,
                "Authorization": f"Bearer {settings.key}",
                "Accept": "application/json",
            }
        )

    def upsert_subscription(
        self,
        *,
        device_token: str,
        platform: str,
        schedule_block_sweep_id: int,
        latitude: float,
        longitude: float,
        lead_minutes: int,
    ) -> SubscriptionRecord:
        """
        Insert or update a subscription keyed by device token.

        Returns the stored record.
        """
        payload = {
            "device_token": device_token,
            "platform": platform,
            "schedule_block_sweep_id": schedule_block_sweep_id,
            "location": f"SRID=4326;POINT({longitude} {latitude})",
            "lead_minutes": lead_minutes,
        }
        params = {"on_conflict": "device_token"}
        headers = {"Prefer": "resolution=merge-duplicates,return=representation"}
        try:
            response = self.session.post(
                self.settings.rest_endpoint,
                params=params,
                headers=headers,
                json=[payload],
                timeout=(5, 10),
            )
        except requests.exceptions.RequestException as exc:
            raise RepositoryConnectionError(
                "Unable to connect to subscription database"
            ) from exc

        self._raise_for_errors(response, "creating subscription")
        body = response.json() if response.content else []
        if not body:
            raise RepositoryConnectionError("Subscription database returned no content")

        return SubscriptionRecord.model_validate(body[0])

    def get_by_device_token(self, device_token: str) -> SubscriptionRecord:
        """Fetch a subscription by device token."""
        params = {
            "device_token": f"eq.{device_token}",
            "select": "device_token,platform,schedule_block_sweep_id,lead_minutes,last_notified_at",
            "limit": 1,
        }
        try:
            response = self.session.get(
                self.settings.rest_endpoint, params=params, timeout=(5, 10)
            )
        except requests.exceptions.RequestException as exc:
            raise RepositoryConnectionError(
                "Unable to connect to subscription database"
            ) from exc

        self._raise_for_errors(response, "fetching subscription")
        payload = response.json()
        if not payload:
            raise SubscriptionNotFoundError("Subscription not found")

        return SubscriptionRecord.model_validate(payload[0])

    def list_subscriptions(self, *, limit: int = 10000) -> list[SubscriptionRecord]:
        """Fetch a batch of subscriptions (for scheduled processing)."""
        headers = {"Range": f"0-{max(0, limit - 1)}"}
        params = {
            "select": "device_token,platform,schedule_block_sweep_id,lead_minutes,last_notified_at"
        }
        try:
            response = self.session.get(
                self.settings.rest_endpoint,
                params=params,
                headers=headers,
                timeout=(10, 20),
            )
        except requests.exceptions.RequestException as exc:
            raise RepositoryConnectionError(
                "Unable to connect to subscription database"
            ) from exc

        self._raise_for_errors(response, "listing subscriptions")
        payload = response.json() or []
        return [SubscriptionRecord.model_validate(item) for item in payload]

    def mark_notified(self, device_token: str, *, notified_at: datetime) -> None:
        """Update last_notified_at after a successful send."""
        params = {"device_token": f"eq.{device_token}"}
        headers = {"Prefer": "return=minimal"}
        payload = {"last_notified_at": notified_at.isoformat()}
        try:
            response = self.session.patch(
                self.settings.rest_endpoint,
                params=params,
                headers=headers,
                json=payload,
                timeout=(5, 10),
            )
        except requests.exceptions.RequestException as exc:
            raise RepositoryConnectionError(
                "Unable to connect to subscription database"
            ) from exc

        self._raise_for_errors(response, "marking subscription notified")

    def delete_by_device_token(self, device_token: str) -> None:
        """Delete a subscription."""
        params = {"device_token": f"eq.{device_token}"}
        headers = {"Prefer": "return=representation"}
        try:
            response = self.session.delete(
                self.settings.rest_endpoint,
                params=params,
                headers=headers,
                timeout=(5, 10),
            )
        except requests.exceptions.RequestException as exc:
            raise RepositoryConnectionError(
                "Unable to connect to subscription database"
            ) from exc

        self._raise_for_errors(response, "deleting subscription")
        if response.status_code == 204:
            return
        deleted = response.json() if response.content else []
        if not deleted:
            raise SubscriptionNotFoundError("Subscription not found")

    @staticmethod
    def _raise_for_errors(response: requests.Response, action: str) -> None:
        if response.status_code in {401, 403}:
            raise RepositoryAuthenticationError(
                "Subscription database authentication failed"
            )
        if response.status_code >= 500:
            raise RepositoryConnectionError(
                f"Subscription database query failed while {action}"
            )
        if not response.ok:
            raise RepositoryConnectionError(
                f"Subscription database error while {action}: {response.text}"
            )
