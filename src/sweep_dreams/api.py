import os
from datetime import datetime
from functools import lru_cache
from typing import Any

import requests
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from sweep_dreams.schedules import PACIFIC_TZ, SweepingSchedule, next_sweep_window


class SupabaseSettings(BaseModel):
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


@lru_cache(maxsize=1)
def get_supabase_settings() -> SupabaseSettings:
    load_dotenv()
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    table = os.getenv("SUPABASE_TABLE")
    rpc_function = os.getenv("SUPABASE_RPC_FUNCTION", "schedules_near")
    if not url or not key:
        raise RuntimeError("Supabase credentials are not configured.")
    return SupabaseSettings(url=url, key=key, table=table, rpc_function=rpc_function)


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

    def closest_schedules(self, *, latitude: float, longitude: float) -> list[SweepingSchedule]:
        body = {"lon": longitude, "lat": latitude}
        try:
            response = self.session.post(
                self.settings.rpc_endpoint, json=body, timeout=(5, 10)
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

        return [SweepingSchedule.model_validate(item) for item in payload]


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


class ScheduleWithWindow(BaseModel):
    schedule: SweepingSchedule
    next_sweep_start: datetime
    next_sweep_end: datetime


class CheckLocationResponse(BaseModel):
    request_point: LocationRequest
    schedules: list[ScheduleWithWindow]
    timezone: str = Field(default=PACIFIC_TZ.key)


app = FastAPI(title="Sweep Dreams API")

# Enable CORS for Flutter web app and other web clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:*",  # Flutter web dev server (various ports)
        "http://127.0.0.1:*",
        "*",  # Allow all origins in development
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _handle_check_location(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    supabase: SupabaseSchedulesClient = Depends(supabase_client_dep),
) -> CheckLocationResponse:
    schedules = supabase.closest_schedules(latitude=latitude, longitude=longitude)

    schedule_windows: list[ScheduleWithWindow] = []
    for schedule in schedules:
        try:
            start, end = next_sweep_window(schedule)
        except ValueError as exc:
            raise HTTPException(status_code=500, detail=str(exc)) from exc
        schedule_windows.append(
            ScheduleWithWindow(
                schedule=schedule,
                next_sweep_start=start,
                next_sweep_end=end,
            )
        )

    return CheckLocationResponse(
        request_point=LocationRequest(latitude=latitude, longitude=longitude),
        schedules=schedule_windows,
        timezone=PACIFIC_TZ.key,
    )


@app.get("/health")
@app.head("/health")
def health_check():
    """Health check endpoint for monitoring and load balancers."""
    return {"status": "ok"}


@app.get("/check-location", response_model=CheckLocationResponse)
def check_location(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    supabase: SupabaseSchedulesClient = Depends(supabase_client_dep),
):
    return _handle_check_location(latitude=latitude, longitude=longitude, supabase=supabase)


@app.get("/api/check-location", response_model=CheckLocationResponse)
def check_location_api(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    supabase: SupabaseSchedulesClient = Depends(supabase_client_dep),
):
    return _handle_check_location(latitude=latitude, longitude=longitude, supabase=supabase)
