"""API request and response models."""

from datetime import datetime

from pydantic import BaseModel, Field

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
        next_sweep_end: datetime
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
