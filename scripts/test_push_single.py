"""Send a test push notification to a single device.

Usage:
    # First, get your device token from Supabase after subscribing in the app

    # Then send a test notification:
    uv run python scripts/test_push_single.py YOUR_DEVICE_TOKEN

    # Or with a custom message:
    uv run python scripts/test_push_single.py YOUR_DEVICE_TOKEN --title "Test" --body "Hello!"

Environment variables (loaded from .env at project root):
    FCM_SERVICE_ACCOUNT_JSON - Firebase service account JSON (raw or base64)
    FCM_PROJECT_ID - (optional) Firebase project ID if not in service account
"""

import argparse
import sys
from pathlib import Path

from dotenv import load_dotenv

# Load .env from project root
env_path = Path(__file__).parent.parent / ".env"
load_dotenv(env_path)

from send_notifications import load_service_account, send_push_v1  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Send a test push notification to a single device"
    )
    parser.add_argument(
        "device_token",
        help="The FCM device token to send to (get this from the subscriptions table)",
    )
    parser.add_argument(
        "--title",
        default="🧹 Test notification",
        help="Notification title",
    )
    parser.add_argument(
        "--body",
        default="This is a test push from Sweep Dreams!",
        help="Notification body",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't actually send, just log what would be sent",
    )
    args = parser.parse_args()

    # Safety check: require explicit token
    if not args.device_token or len(args.device_token) < 20:
        print("ERROR: You must provide a valid device token as the first argument")
        print(
            "Get it from Supabase: SELECT device_token FROM subscriptions ORDER BY created_at DESC LIMIT 1"
        )
        sys.exit(1)

    print("Loading Firebase credentials...")
    creds, project_id = load_service_account()
    print(f"Project ID: {project_id}")

    print(
        f"\nSending to device token: {args.device_token[:20]}...{args.device_token[-10:]}"
    )
    print(f"Title: {args.title}")
    print(f"Body: {args.body}")
    print(f"Dry run: {args.dry_run}")
    print()

    try:
        send_push_v1(
            creds,
            project_id,
            args.device_token,
            title=args.title,
            body=args.body,
            data={"test": "true"},
            dry_run=args.dry_run,
        )
        if args.dry_run:
            print("DRY RUN: Would have sent notification (no actual push sent)")
        else:
            print("SUCCESS: Notification sent!")
    except Exception as e:
        print(f"ERROR: Failed to send notification: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
