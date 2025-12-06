"""Scheduled notification sender for Sweep Dreams."""

import base64
import json
import logging
import os
from datetime import datetime, timedelta

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

from sweep_dreams.domain.calendar import earliest_sweep_window
from sweep_dreams.domain.models import PACIFIC_TZ, SweepingSchedule
from sweep_dreams.parsing.converters import sweeping_schedules_to_blocks
from sweep_dreams.repositories.subscriptions import (
    SubscriptionRecord,
    SupabaseSubscriptionRepository,
    SupabaseSubscriptionSettings,
)
from sweep_dreams.repositories.supabase import (
    SupabaseScheduleRepository,
    SupabaseSettings,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("send_notifications")


def load_cadence_minutes() -> int:
    try:
        return int(os.getenv("NOTIFY_CADENCE_MINUTES", "60"))
    except ValueError:
        return 60


def should_send(
    record: SubscriptionRecord,
    schedule: SweepingSchedule,
    *,
    now: datetime,
    window_end: datetime,
) -> tuple[bool, datetime | None, datetime | None, datetime | None]:
    """Determine whether to notify; returns flag and window times."""
    block_schedules = sweeping_schedules_to_blocks([schedule])
    if not block_schedules:
        return False, None, None, None
    block_schedule = block_schedules[0]
    start, end = earliest_sweep_window(block_schedule, now=now, tz=PACIFIC_TZ)

    # If sweep has already started, don't notify
    if start <= now:
        return False, start, end, None

    # Calculate ideal notification time
    notify_at = start - timedelta(minutes=record.lead_minutes)

    # If ideal notification time has passed but sweep hasn't started, notify immediately (late notification)
    if notify_at < now:
        # Check if we've already notified for this sweep window
        if record.last_notified_at and record.last_notified_at >= start:
            return False, start, end, now
        return True, start, end, now

    # Ideal notification time is in the future - check if it's within the cadence window
    if notify_at >= window_end:
        return False, start, end, notify_at

    # Check if we've already notified at or after the ideal time
    if record.last_notified_at and record.last_notified_at >= notify_at:
        return False, start, end, notify_at

    return True, start, end, notify_at


def load_service_account() -> tuple[service_account.Credentials, str]:
    """Load service account credentials for FCM v1."""
    raw = os.getenv("FCM_SERVICE_ACCOUNT_JSON")
    if not raw:
        raise RuntimeError("FCM_SERVICE_ACCOUNT_JSON is required for FCM v1")

    try:
        if not raw.strip().startswith("{"):
            raw = base64.b64decode(raw).decode("utf-8")
        info = json.loads(raw)
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError("Failed to parse FCM service account JSON") from exc

    scopes = ["https://www.googleapis.com/auth/firebase.messaging"]
    creds = service_account.Credentials.from_service_account_info(info, scopes=scopes)
    project_id = os.getenv("FCM_PROJECT_ID", info.get("project_id"))
    if not project_id:
        raise RuntimeError("project_id not found in service account or FCM_PROJECT_ID")
    return creds, project_id


def send_push_v1(
    creds: service_account.Credentials,
    project_id: str,
    device_token: str,
    *,
    title: str,
    body: str,
    data: dict[str, str],
    dry_run: bool = False,
) -> None:
    """Send a push via FCM HTTP v1 using a service account."""
    if dry_run:
        logger.info("DRY RUN: would send to %s with %s", device_token, data)
        return

    scoped_creds = creds.with_scopes(
        ["https://www.googleapis.com/auth/firebase.messaging"]
    )
    scoped_creds.refresh(Request())

    headers = {
        "Authorization": f"Bearer {scoped_creds.token}",
        "Content-Type": "application/json",
    }
    payload = {
        "message": {
            "token": device_token,
            "notification": {"title": title, "body": body},
            "data": data,
        }
    }
    response = requests.post(
        f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
        json=payload,
        headers=headers,
        timeout=10,
    )
    if not response.ok:
        raise RuntimeError(f"FCM error {response.status_code}: {response.text}")


def main() -> None:
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    subs_table = os.getenv("SUPABASE_SUBSCRIPTIONS_TABLE", "subscriptions")
    schedules_table = os.getenv("SUPABASE_TABLE", "schedules")
    rpc_fn = os.getenv("SUPABASE_RPC_FUNCTION", "schedules_near")
    sa_creds = None
    project_id = None
    if os.getenv("FCM_SERVICE_ACCOUNT_JSON"):
        sa_creds, project_id = load_service_account()
    dry_run = os.getenv("NOTIFY_DRY_RUN", "").lower() == "true" or sa_creds is None

    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_KEY must be set")

    cadence_minutes = load_cadence_minutes()
    now = datetime.now(PACIFIC_TZ)
    window_end = now + timedelta(minutes=cadence_minutes)
    logger.info("Starting notification sweep window %s -> %s", now, window_end)

    schedule_repo = SupabaseScheduleRepository(
        SupabaseSettings(url=url, key=key, table=schedules_table, rpc_function=rpc_fn)
    )
    subs_repo = SupabaseSubscriptionRepository(
        SupabaseSubscriptionSettings(url=url, key=key, table=subs_table)
    )

    subscriptions: list[SubscriptionRecord] = subs_repo.list_subscriptions()
    logger.info("Fetched %d subscriptions", len(subscriptions))

    schedule_cache: dict[int, SweepingSchedule] = {}
    sent = 0
    skipped = 0

    for record in subscriptions:
        schedule = schedule_cache.get(record.schedule_block_sweep_id)
        if schedule is None:
            try:
                schedule = schedule_repo.get_schedule_by_block_sweep_id(
                    record.schedule_block_sweep_id
                )
                schedule_cache[record.schedule_block_sweep_id] = schedule
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "Skipping subscription for block_sweep_id=%s: %s",
                    record.schedule_block_sweep_id,
                    exc,
                )
                skipped += 1
                continue

        should, start, end, notify_at = should_send(
            record, schedule, now=now, window_end=window_end
        )
        if not should:
            skipped += 1
            continue

        title = "Street sweeping reminder"
        body = f"Sweeping starts at {start.strftime('%-I:%M %p')} and ends at {end.strftime('%-I:%M %p')}."
        data = {
            "schedule_block_sweep_id": str(record.schedule_block_sweep_id),
            "next_sweep_start": start.isoformat(),
            "next_sweep_end": end.isoformat(),
        }

        try:
            send_push_v1(
                sa_creds,
                project_id or "",
                record.device_token,
                title=title,
                body=body,
                data=data,
                dry_run=dry_run,
            )
            subs_repo.mark_notified(record.device_token, notified_at=notify_at or now)
            sent += 1
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Failed to send to device_token=%s: %s",
                record.device_token,
                exc,
            )
            skipped += 1

    logger.info("Done. Sent=%d Skipped=%d DryRun=%s", sent, skipped, dry_run)


if __name__ == "__main__":
    main()
