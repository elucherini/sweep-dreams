from contextlib import contextmanager
from datetime import datetime
from fastapi import HTTPException
from fastapi.testclient import TestClient

from sweep_dreams import api
from sweep_dreams.domain.models import PACIFIC_TZ
from sweep_dreams.domain.calendar import next_sweep_window
from sweep_dreams import domain


@contextmanager
def client_with_supabase_override(supabase_client):
    api.app.dependency_overrides[api.supabase_client_dep] = lambda: supabase_client
    try:
        with TestClient(api.app) as client:
            yield client
    finally:
        api.app.dependency_overrides.pop(api.supabase_client_dep, None)


def test_check_location_returns_schedule(monkeypatch, schedule_factory):
    schedule = schedule_factory(week_day="Fri", weeks=(2, 4), from_hour=12, to_hour=14)
    fixed_now = datetime(2024, 3, 6, 10, tzinfo=PACIFIC_TZ)
    expected_start, expected_end = next_sweep_window(schedule, now=fixed_now)

    class StubSupabaseClient:
        def __init__(self) -> None:
            self.calls: list[tuple[float, float]] = []

        def closest_schedules(self, *, latitude: float, longitude: float):
            self.calls.append((latitude, longitude))
            return [schedule]

    stub_client = StubSupabaseClient()

    def next_window_for_test(sched, *, now=None, tz=None):
        return next_sweep_window(sched, now=fixed_now, tz=tz)

    # Patch at the domain.calendar level where it's used
    monkeypatch.setattr(domain.calendar, "next_sweep_window", next_window_for_test)

    with client_with_supabase_override(stub_client) as client:
        response = client.get(
            "/check-location",
            params={"latitude": 37.77, "longitude": -122.42},
        )

    if response.status_code != 200:
        print(f"Error response: {response.json()}")
    assert response.status_code == 200
    payload = response.json()
    assert stub_client.calls == [(37.77, -122.42)]
    assert payload["request_point"] == {"latitude": 37.77, "longitude": -122.42}
    assert payload["timezone"] == PACIFIC_TZ.key
    assert len(payload["schedules"]) == 1
    schedule_payload = payload["schedules"][0]
    assert schedule_payload["block_sweep_id"] == schedule.block_sweep_id
    assert (
        datetime.fromisoformat(schedule_payload["next_sweep_start"]) == expected_start
    )
    assert datetime.fromisoformat(schedule_payload["next_sweep_end"]) == expected_end
    # Now checking BlockSchedule structure
    block_schedule = schedule_payload["schedule"]
    assert block_schedule["block"]["cnn"] == schedule.cnn
    assert len(block_schedule["rules"]) >= 1
    # JSON serialization converts tuples to lists
    assert block_schedule["line"] == [list(coord) for coord in schedule.line]


def test_check_location_propagates_supabase_errors():
    class FailingClient:
        def closest_schedules(self, *, latitude: float, longitude: float):
            raise HTTPException(
                status_code=404, detail="No schedule found near location."
            )

    with client_with_supabase_override(FailingClient()) as client:
        response = client.get(
            "/check-location",
            params={"latitude": 37.77, "longitude": -122.42},
        )

    assert response.status_code == 404
    assert response.json() == {"detail": "No schedule found near location."}


def test_check_location_uses_earliest_block_sweep_id(monkeypatch, schedule_factory):
    early_schedule = schedule_factory(
        week_day="Wed",
        weeks=(1,),
        from_hour=2,
        to_hour=4,
        overrides={"block_sweep_id": 101},
    )
    later_schedule = schedule_factory(
        week_day="Thu",
        weeks=(1,),
        from_hour=2,
        to_hour=4,
        overrides={"block_sweep_id": 202},
    )
    fixed_now = datetime(2024, 3, 4, 10, tzinfo=PACIFIC_TZ)
    expected_start, expected_end = next_sweep_window(early_schedule, now=fixed_now)

    def next_window_for_test(sched, *, now=None, tz=None):
        return next_sweep_window(sched, now=fixed_now, tz=tz)

    monkeypatch.setattr(domain.calendar, "next_sweep_window", next_window_for_test)

    class StubSupabaseClient:
        def __init__(self) -> None:
            self.calls: list[tuple[float, float]] = []

        def closest_schedules(self, *, latitude: float, longitude: float):
            self.calls.append((latitude, longitude))
            return [later_schedule, early_schedule]

    with client_with_supabase_override(StubSupabaseClient()) as client:
        response = client.get(
            "/check-location",
            params={"latitude": 37.77, "longitude": -122.42},
        )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["schedules"]) == 1
    schedule_payload = payload["schedules"][0]
    assert schedule_payload["block_sweep_id"] == early_schedule.block_sweep_id
    assert (
        datetime.fromisoformat(schedule_payload["next_sweep_start"]) == expected_start
    )
    assert datetime.fromisoformat(schedule_payload["next_sweep_end"]) == expected_end
