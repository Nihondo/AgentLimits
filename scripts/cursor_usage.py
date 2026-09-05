#!/usr/bin/env python3
"""Emit Cursor usage as an AgentLimits custom usage snapshot."""

import json
import math
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PROVIDER_ID = "cursor"
CURRENT_PERIOD_USAGE_ENDPOINT = (
    "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
)
ACCESS_TOKEN_KEY = "cursorAuth/accessToken"
DEFAULT_DATABASE_PATH = Path.home() / "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
REQUEST_TIMEOUT_SECONDS = 20


class CursorUsageError(Exception):
    """ユーザーに表示できるCursor使用量取得エラーです。"""


def fail(message: str) -> None:
    """標準エラー出力へ理由を出して失敗終了します。"""
    print(f"Cursor usage: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_access_token(database_path: Path) -> str:
    """Cursorのグローバル状態DBからセッションアクセストークンを読み取ります。"""
    if not database_path.is_file():
        raise CursorUsageError(f"Cursor state database was not found at {database_path}")

    try:
        database = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)
        try:
            row = database.execute(
                "SELECT value FROM ItemTable WHERE key = ?",
                (ACCESS_TOKEN_KEY,),
            ).fetchone()
        finally:
            database.close()
    except sqlite3.Error as error:
        raise CursorUsageError(f"could not read Cursor state database: {error}") from error

    if row is None or not isinstance(row[0], str) or not row[0]:
        raise CursorUsageError("Cursor access token was not found; sign in to Cursor first")
    return row[0]


def fetch_current_period_usage(access_token: str) -> dict[str, Any]:
    """Cursor内部ダッシュボードAPIへJSONリクエストを送り、オブジェクトを取得します。"""
    request = Request(
        CURRENT_PERIOD_USAGE_ENDPOINT,
        data=b"{}",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "Accept": "application/json",
            "User-Agent": "AgentLimits Cursor usage script",
        },
    )
    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            data = json.load(response)
    except HTTPError as error:
        raise CursorUsageError(f"current-period usage API returned HTTP {error.code}") from error
    except (URLError, TimeoutError, json.JSONDecodeError) as error:
        raise CursorUsageError(f"current-period usage API request failed: {error}") from error

    if not isinstance(data, dict):
        raise CursorUsageError("current-period usage API returned an unexpected response")
    return data


def parse_timestamp(value: Any, field_name: str) -> datetime:
    """Cursor APIのUnixミリ秒またはISO 8601日時をUTC日時として解釈します。"""
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
        timestamp = value / 1000 if value > 1_000_000_000_000 else value
        return datetime.fromtimestamp(timestamp, tz=timezone.utc)
    if not isinstance(value, str):
        raise CursorUsageError(f"current-period usage API does not contain {field_name}")

    if value.isdecimal():
        return datetime.fromtimestamp(int(value) / 1000, tz=timezone.utc)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise CursorUsageError(f"current-period usage API returned an invalid {field_name}") from error
    return parsed.replace(tzinfo=parsed.tzinfo or timezone.utc).astimezone(timezone.utc)


def parse_used_percent(plan_usage: dict[str, Any]) -> float:
    """Cursorの課金周期使用率を取得し、未提供なら金額から計算します。"""
    percentage = plan_usage.get("totalPercentUsed")
    if isinstance(percentage, (int, float)) and not isinstance(percentage, bool) and math.isfinite(percentage):
        return min(100, max(0, round(percentage, 2)))

    total_spend = plan_usage.get("totalSpend")
    limit = plan_usage.get("limit")
    if (
        isinstance(total_spend, (int, float))
        and not isinstance(total_spend, bool)
        and math.isfinite(total_spend)
        and isinstance(limit, (int, float))
        and not isinstance(limit, bool)
        and math.isfinite(limit)
        and limit > 0
    ):
        return min(100, max(0, round(total_spend / limit * 100, 2)))
    raise CursorUsageError("current-period usage API does not provide a usable plan limit")


def build_snapshot(current_period_usage: dict[str, Any]) -> dict[str, Any]:
    """現行Cursor APIの課金周期使用量をカスタム使用量スナップショットへ変換します。"""
    plan_usage = current_period_usage.get("planUsage")
    if not isinstance(plan_usage, dict):
        raise CursorUsageError("current-period usage API does not contain planUsage")

    cycle_start = parse_timestamp(current_period_usage.get("billingCycleStart"), "billingCycleStart")
    reset_at = parse_timestamp(current_period_usage.get("billingCycleEnd"), "billingCycleEnd")
    duration_seconds = (reset_at - cycle_start).total_seconds()
    if not math.isfinite(duration_seconds) or duration_seconds <= 0:
        raise CursorUsageError("current-period usage API returned an invalid billing cycle")

    return {
        "schemaVersion": 1,
        "provider": PROVIDER_ID,
        "fetchedAt": format_timestamp(datetime.now(timezone.utc)),
        "windows": [
            {
                "kind": "1month",
                "title": "Cursor plan usage",
                "usedPercent": parse_used_percent(plan_usage),
                "resetAt": format_timestamp(reset_at),
                "durationSeconds": duration_seconds,
            }
        ],
    }


def format_timestamp(value: datetime) -> str:
    """AgentLimits契約に必要なUTC ISO 8601文字列へ変換します。"""
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def main() -> None:
    """Cursorの認証情報を使ってカスタムJSONを標準出力へ1件だけ出力します。"""
    access_token = load_access_token(DEFAULT_DATABASE_PATH)
    snapshot = build_snapshot(fetch_current_period_usage(access_token))
    print(json.dumps(snapshot, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except CursorUsageError as error:
        fail(str(error))
