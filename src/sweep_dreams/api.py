import os
from datetime import datetime
from functools import lru_cache
from typing import Any

import requests
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from sweep_dreams.schedules import PACIFIC_TZ, SweepingSchedule, next_sweep_window


class SupabaseSettings(BaseModel):
    url: str
    key: str
    table: str = "schedules"

    @property
    def rest_endpoint(self) -> str:
        return f"{self.url.rstrip('/')}/rest/v1/{self.table}"


@lru_cache(maxsize=1)
def get_supabase_settings() -> SupabaseSettings:
    load_dotenv()
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    table = os.getenv("SUPABASE_TABLE", "schedules")
    if not url or not key:
        raise RuntimeError("Supabase credentials are not configured.")
    return SupabaseSettings(url=url, key=key, table=table)


class SupabaseSchedulesClient:
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

    def closest_schedule(self, *, latitude: float, longitude: float) -> SweepingSchedule:
        order_expr = f"line.<->.st_setsrid(st_point({longitude},{latitude}),4326)"
        params = {"select": "*", "order": order_expr, "limit": 1}
        try:
            response = self.session.get(
                self.settings.rest_endpoint, params=params, timeout=(5, 10)
            )
        except requests.exceptions.RequestException as exc:
            raise HTTPException(status_code=502, detail="Error reaching Supabase.") from exc

        if response.status_code in {401, 403}:
            raise HTTPException(status_code=500, detail="Supabase authentication failed.")
        if response.status_code >= 500:
            raise HTTPException(status_code=502, detail="Supabase query failed.")
        if not response.ok:
            raise HTTPException(status_code=response.status_code, detail=response.text)

        payload: list[dict[str, Any]] = response.json()
        if not payload:
            raise HTTPException(status_code=404, detail="No schedule found near location.")

        return SweepingSchedule.model_validate(payload[0])


@lru_cache(maxsize=1)
def get_supabase_client() -> SupabaseSchedulesClient:
    return SupabaseSchedulesClient(get_supabase_settings())


def supabase_client_dep() -> SupabaseSchedulesClient:
    try:
        return get_supabase_client()
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


class LocationRequest(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class CheckLocationResponse(BaseModel):
    request_point: LocationRequest
    schedule: SweepingSchedule
    next_sweep_start: datetime
    next_sweep_end: datetime
    timezone: str = Field(default=PACIFIC_TZ.key)


app = FastAPI(title="Sweep Dreams API")


@app.get("/check-location", response_model=CheckLocationResponse)
def check_location(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    supabase: SupabaseSchedulesClient = Depends(supabase_client_dep),
):
    schedule = supabase.closest_schedule(latitude=latitude, longitude=longitude)
    try:
        start, end = next_sweep_window(schedule)
    except ValueError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return CheckLocationResponse(
        request_point=LocationRequest(latitude=latitude, longitude=longitude),
        schedule=schedule,
        next_sweep_start=start,
        next_sweep_end=end,
        timezone=PACIFIC_TZ.key,
    )
