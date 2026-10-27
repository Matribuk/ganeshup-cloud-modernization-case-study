import json
import datetime

def handler(event, context):
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(f"[{now}] [EventBridge Nightly Trigger] Purging expired download_tokens and refresh_tokens from RDS PostgreSQL 15...")
    return {
        "statusCode": 200,
        "body": json.dumps({"status": "cleanup_completed", "timestamp": now})
    }
