"""API request and response models."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from sweep_dreams.domain.models import PACIFIC_TZ, BlockSchedule
from sweep_dreams.domain.formatting import schedule_to_human


class LocationRequest(BaseModel):
    """Request model for location-based queries."""

    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class BlockScheduleResponse(BaseModel):
    """Response model for a block schedule with computed next sweep."""

    schedule: BlockSchedule
    human_rules: list[str]
    next_sweep_start: datetime
    next_sweep_end: datetime

    @staticmethod
    def build(
        block_schedule: BlockSchedule,
        next_sweep_start: datetime,
        next_sweep_end: datetime,
    ) -> "BlockScheduleResponse":
        """
        Build a BlockScheduleResponse with human-readable rules.

        Args:
            block_schedule: The block schedule
            next_sweep_start: Start time of next sweep
            next_sweep_end: End time of next sweep

        Returns:
            BlockScheduleResponse instance
        """
        return BlockScheduleResponse(
            schedule=block_schedule,
            human_rules=schedule_to_human(block_schedule),
            next_sweep_start=next_sweep_start,
            next_sweep_end=next_sweep_end,
        )


class CheckLocationResponse(BaseModel):
    """Response model for checking schedules at a location."""

    request_point: LocationRequest
    schedules: list[BlockScheduleResponse]
    timezone: str = Field(default=PACIFIC_TZ.key)


class SubscribeRequest(BaseModel):
    """Request body for creating or updating a subscription."""

    device_token: str
    platform: Literal["web", "ios", "android"]
    schedule_block_sweep_id: int
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    lead_minutes: int = Field(default=60, gt=0)

    @field_validator("lead_minutes")
    @classmethod
    def validate_lead_minutes(cls, value: int) -> int:
        if value % 15 != 0:
            raise ValueError("lead_minutes must be a multiple of 15 minutes")
        return value


class SubscriptionStatus(BaseModel):
    """Response model representing a stored subscription and computed window."""

    device_token: str
    platform: str
    schedule_block_sweep_id: int
    lead_minutes: int
    schedule: BlockScheduleResponse
    timezone: str = Field(default=PACIFIC_TZ.key)
