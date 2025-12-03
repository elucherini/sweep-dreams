"""Subscription orchestration logic."""

from pydantic import BaseModel

from sweep_dreams.api.models import (
    SubscribeRequest,
    SubscriptionStatus,
    BlockScheduleResponse,
)
from sweep_dreams.domain.calendar import earliest_sweep_window
from sweep_dreams.parsing.converters import sweeping_schedules_to_blocks
from sweep_dreams.repositories.exceptions import ScheduleNotFoundError
from sweep_dreams.repositories.subscriptions import (
    SupabaseSubscriptionRepository,
)
from sweep_dreams.repositories.supabase import SupabaseScheduleRepository


class SubscriptionService(BaseModel):
    """High-level operations for managing subscriptions."""

    schedule_repository: SupabaseScheduleRepository
    subscription_repository: SupabaseSubscriptionRepository

    model_config = {"arbitrary_types_allowed": True}

    def _block_schedule_response(self, block_sweep_id: int) -> BlockScheduleResponse:
        schedule = self.schedule_repository.get_schedule_by_block_sweep_id(
            block_sweep_id
        )
        block_schedules = sweeping_schedules_to_blocks([schedule])
        if not block_schedules:
            raise ScheduleNotFoundError("No schedule found for subscription")
        block_schedule = block_schedules[0]
        start, end = earliest_sweep_window(block_schedule)
        return BlockScheduleResponse.build(block_schedule, start, end)

    def subscribe(self, request: SubscribeRequest) -> SubscriptionStatus:
        """Create or update a subscription and return its next sweep window."""
        record = self.subscription_repository.upsert_subscription(
            device_token=request.device_token,
            platform=request.platform,
            schedule_block_sweep_id=request.schedule_block_sweep_id,
            latitude=request.latitude,
            longitude=request.longitude,
            lead_minutes=request.lead_minutes,
        )
        schedule_response = self._block_schedule_response(
            record.schedule_block_sweep_id
        )
        return SubscriptionStatus(
            device_token=record.device_token,
            platform=record.platform,
            schedule_block_sweep_id=record.schedule_block_sweep_id,
            lead_minutes=record.lead_minutes,
            schedule=schedule_response,
        )

    def get_status(self, device_token: str) -> SubscriptionStatus:
        """Return the subscription and its computed next window."""
        record = self.subscription_repository.get_by_device_token(device_token)
        schedule_response = self._block_schedule_response(
            record.schedule_block_sweep_id
        )
        return SubscriptionStatus(
            device_token=record.device_token,
            platform=record.platform,
            schedule_block_sweep_id=record.schedule_block_sweep_id,
            lead_minutes=record.lead_minutes,
            schedule=schedule_response,
        )

    def delete(self, device_token: str) -> None:
        """Delete a subscription."""
        self.subscription_repository.delete_by_device_token(device_token)
