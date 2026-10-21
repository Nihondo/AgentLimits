#!/usr/bin/env python3
"""Emit Google Antigravity (agy CLI / IDE) Gemini quota as an AgentLimits custom usage snapshot."""

from __future__ import annotations

import getpass
import json
import subprocess
import sys
from base64 import b64decode
from datetime import datetime, timezone
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PROVIDER_ID = "antigravity"

# `agy` keeps its OAuth token under the historical Gemini CLI keychain item:
# service "gemini" (renamed from Gemini CLI), account "antigravity".
KEYCHAIN_SERVICE = "gemini"
KEYCHAIN_ACCOUNT = "antigravity"
KEYRING_BASE64_PREFIX = "go-keyring-base64:"

# This script never performs the OAuth refresh grant itself (that would
# require embedding/extracting Antigravity's own OAuth client secret out of
# its binary). Instead, when the cached access token is at/near expiry, it
# shells out to a lightweight authenticated `agy` subcommand so `agy` itself
# performs the refresh and rewrites the Keychain entry, then re-reads it.
REFRESH_BUFFER_SECONDS = 60
AGY_REFRESH_COMMAND = ["agy", "models"]
AGY_REFRESH_TIMEOUT_SECONDS = 15

# `retrieveUserQuotaSummary` is the same endpoint Antigravity's own "Models &
# Quota" panel uses; it returns the real 5-hour and weekly Gemini buckets with
# a fixed reset cadence. Verified against a real account: it answers HTTP 403
# "no valid license of this product" on a free-tier Antigravity account, and
# only works once the account is on a paid/standard plan — there is no
# request-body workaround for the free tier.
# The hosts do not return the same groups: the daily host may omit the Gemini
# group entirely while the production host includes it, so every host is
# queried and the buckets are merged (see `extract_buckets`).
# The hosts also keep separate usage counters: the Gemini 5h usage can show up
# only on one host (observed: daily's fetchAvailableModels per-model
# `quotaInfo`, while the production host still reported a full bucket), so the
# most-used value across hosts wins (see `merge_bucket`) and the 5h bucket is
# also derived from `fetchAvailableModels` (see `extract_gemini_five_hour_bucket`).
AVAILABLE_MODELS_PATH = "/v1internal:fetchAvailableModels"
# The "Gemini Models" quota group covers the standard Flash/Pro models only
# (per the API's own group description). Special models that `agy models` lists
# (e.g. "gemini-4-argon-*") or image models may be metered separately, so they
# are never used to derive the standard 5h window.
NON_STANDARD_GEMINI_MODEL_MARKERS = ("argon", "image")
CLOUD_QUOTA_HOSTS = (
    "https://daily-cloudcode-pa.googleapis.com",
    "https://cloudcode-pa.googleapis.com",
)
QUOTA_SUMMARY_PATH = "/v1internal:retrieveUserQuotaSummary"

# Headers that identify the caller as the Antigravity IDE. Harmless to send
# and matches what the real client sends for this endpoint.
ANTIGRAVITY_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
        "Antigravity/1.0.0 Chrome/138.0.7204.235 Electron/37.3.1 Safari/537.36"
    ),
    "X-Goog-Api-Client": "google-cloud-sdk vscode_cloudshelleditor/0.1",
    "Client-Metadata": json.dumps({"ideType": "ANTIGRAVITY", "platform": "DARWIN", "pluginType": "GEMINI"}),
}

# Bucket ids observed in a real retrieveUserQuotaSummary response. Antigravity
# also reports "3p-5h"/"3p-weekly" for the shared Claude/GPT-OSS pool, but
# this sample tracks only the native Gemini pool.
BUCKET_ID_BY_KIND = {"5h": "gemini-5h", "1w": "gemini-weekly"}
WINDOW_DURATION_SECONDS = {"5h": 5 * 3600, "1w": 7 * 24 * 3600}

CLOUD_REQUEST_TIMEOUT_SECONDS = 15
CLI_TIMEOUT_SECONDS = 8


class AntigravityUsageError(Exception):
    """ユーザーに表示できるAntigravity使用量取得エラーです。"""


def fail(message: str) -> None:
    """標準エラー出力へ理由を出して失敗終了します。"""
    print(f"Antigravity usage: {message}", file=sys.stderr)
    raise SystemExit(1)


def run_command(args: list[str], timeout: float = CLI_TIMEOUT_SECONDS) -> subprocess.CompletedProcess[str] | None:
    """外部コマンドを実行し、失敗時はNoneを返します。"""
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


# --- Keychainに保存されたOAuthアクセストークンの読み取り(更新は行わない) ----


def load_keychain_access_token() -> tuple[str, datetime | None] | None:
    """Antigravity/agyがmacOSキーチェーンに保存したアクセストークンを読み取ります(更新は行いません)。"""
    accounts = [KEYCHAIN_ACCOUNT]
    try:
        current_user = getpass.getuser()
        if current_user and current_user != KEYCHAIN_ACCOUNT:
            accounts.append(current_user)
    except OSError:
        pass

    raw: str | None = None
    for account in accounts:
        result = run_command(
            ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"]
        )
        if result is not None and result.returncode == 0 and result.stdout.strip():
            raw = result.stdout.strip()
            break
    if raw is None:
        return None

    if raw.startswith(KEYRING_BASE64_PREFIX):
        try:
            raw = b64decode(raw[len(KEYRING_BASE64_PREFIX) :]).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return None

    try:
        blob = json.loads(raw)
    except json.JSONDecodeError:
        return None

    token_object = blob.get("token", blob) if isinstance(blob, dict) else {}
    access_token = token_object.get("access_token") or token_object.get("accessToken")
    if not isinstance(access_token, str) or not access_token:
        return None

    expires_at = parse_optional_timestamp(
        token_object.get("expiry") or token_object.get("expires_at") or token_object.get("expiresAt")
    )
    return access_token, expires_at


def post_cloud_code(host: str, path: str, access_token: str) -> Any:
    """Cloud Codeの内部エンドポイントへ空のJSONボディをPOSTし、デコード済みレスポンスを返します。"""
    request = Request(
        host + path,
        data=b"{}",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": f"Bearer {access_token}",
            **ANTIGRAVITY_HEADERS,
        },
    )
    with urlopen(request, timeout=CLOUD_REQUEST_TIMEOUT_SECONDS) as response:
        return json.load(response)


def fetch_available_model_payloads(access_token: str) -> list[dict[str, Any]]:
    """全ホストからfetchAvailableModelsのレスポンスを取得します(取得できないホストは無視します)。"""
    payloads: list[dict[str, Any]] = []
    for host in CLOUD_QUOTA_HOSTS:
        try:
            payload = post_cloud_code(host, AVAILABLE_MODELS_PATH, access_token)
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError):
            continue
        if isinstance(payload, dict):
            payloads.append(payload)
    return payloads


def fetch_quota_summaries(access_token: str) -> list[dict[str, Any]]:
    """アクセストークンを使い、全ホストからretrieveUserQuotaSummaryのレスポンスを取得します。"""
    summaries: list[dict[str, Any]] = []
    last_error: str | None = None
    for host in CLOUD_QUOTA_HOSTS:
        try:
            summaries.append(post_cloud_code(host, QUOTA_SUMMARY_PATH, access_token))
        except HTTPError as error:
            if error.code == 403:
                raise AntigravityUsageError(
                    "quota API returned 403 (no valid license); retrieveUserQuotaSummary requires an "
                    "Antigravity standard/paid plan, not the free tier"
                ) from error
            if error.code == 401:
                raise AntigravityUsageError(
                    "stored access token was rejected; open Antigravity or run `agy` again to refresh it"
                ) from error
            last_error = f"HTTP {error.code}"
        except (URLError, TimeoutError, json.JSONDecodeError) as error:
            last_error = str(error)
    if not summaries:
        raise AntigravityUsageError(f"quota API was unreachable ({last_error or 'unknown error'})")
    return summaries


# --- レスポンス解析とスナップショット組み立て -------------------------------


def parse_optional_timestamp(value: Any) -> datetime | None:
    """ISO 8601文字列またはUnixエポック(秒/ミリ秒)をUTC日時へ変換します。失敗時はNoneです。"""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        seconds = value / 1000 if value > 1_000_000_000_000 else value
        return datetime.fromtimestamp(seconds, tz=timezone.utc)
    if isinstance(value, str) and value:
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed.astimezone(timezone.utc) if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
        try:
            seconds = float(value)
        except ValueError:
            return None
        return datetime.fromtimestamp(seconds, tz=timezone.utc)
    return None


def is_valid_fraction(value: Any) -> bool:
    """remainingFractionとして使える数値か判定します。"""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def merge_bucket(buckets: dict[str, dict[str, Any]], bucket_id: str, bucket: dict[str, Any]) -> None:
    """同じbucketIdが複数ホストにある場合は、残量が少ない(=使用が反映された)方を採用します。"""
    current = buckets.get(bucket_id)
    if current is None:
        buckets[bucket_id] = bucket
        return
    new_fraction = bucket.get("remainingFraction")
    current_fraction = current.get("remainingFraction")
    if is_valid_fraction(new_fraction) and (
        not is_valid_fraction(current_fraction) or new_fraction < current_fraction
    ):
        buckets[bucket_id] = bucket


def extract_buckets(payloads: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """retrieveUserQuotaSummaryのレスポンス群をbucketId毎のバケット辞書へ統合します。"""
    buckets: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        root = payload.get("response", payload) if isinstance(payload, dict) else {}
        groups = root.get("groups") if isinstance(root, dict) else None
        for group in groups or []:
            for bucket in group.get("buckets") or []:
                bucket_id = bucket.get("bucketId")
                if isinstance(bucket_id, str):
                    merge_bucket(buckets, bucket_id, bucket)
    return buckets


def extract_gemini_five_hour_bucket(payloads: list[dict[str, Any]]) -> dict[str, Any] | None:
    """fetchAvailableModelsのGeminiモデル別quotaInfoから、5hバケット相当を組み立てます。

    ホストによってはretrieveUserQuotaSummaryがGeminiグループを返さず、別のホストでは使用量が
    反映されないことがあるため、使用量が反映されるこちらの値で補完します。Geminiモデルは同じ
    5hプールを共有するため、最も残量が少ないモデルの値を採用します。
    """
    now = datetime.now(timezone.utc)
    selected: dict[str, Any] | None = None
    for payload in payloads:
        models = payload.get("models")
        if not isinstance(models, dict):
            continue
        for model_id, model in models.items():
            if not (isinstance(model_id, str) and model_id.startswith("gemini-") and isinstance(model, dict)):
                continue
            if any(marker in model_id for marker in NON_STANDARD_GEMINI_MODEL_MARKERS):
                continue
            quota = model.get("quotaInfo")
            if not isinstance(quota, dict):
                continue
            fraction = quota.get("remainingFraction")
            reset_at = parse_optional_timestamp(quota.get("resetTime"))
            if not is_valid_fraction(fraction) or reset_at is None:
                continue
            # 週次など5hより長い期間のquotaInfoは対象外にする。
            if (reset_at - now).total_seconds() > WINDOW_DURATION_SECONDS["5h"] + REFRESH_BUFFER_SECONDS:
                continue
            if selected is None or fraction < selected["remainingFraction"]:
                selected = {
                    "bucketId": BUCKET_ID_BY_KIND["5h"],
                    "remainingFraction": fraction,
                    "resetTime": quota["resetTime"],
                }
    return selected


def build_windows(buckets: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    """Geminiの5h/weeklyバケットをAgentLimitsのウィンドウ配列へ変換します。"""
    windows: list[dict[str, Any]] = []
    for kind, bucket_id in BUCKET_ID_BY_KIND.items():
        bucket = buckets.get(bucket_id)
        if bucket is None:
            continue
        remaining_fraction = bucket.get("remainingFraction")
        if not isinstance(remaining_fraction, (int, float)) or isinstance(remaining_fraction, bool):
            continue

        used_percent = min(100.0, max(0.0, round((1 - remaining_fraction) * 100, 2)))
        window: dict[str, Any] = {"kind": kind, "usedPercent": used_percent}

        reset_at = parse_optional_timestamp(bucket.get("resetTime"))
        if reset_at is not None:
            window["resetAt"] = format_timestamp(reset_at)
            window["durationSeconds"] = WINDOW_DURATION_SECONDS[kind]
        windows.append(window)
    return windows


def format_timestamp(value: datetime) -> str:
    """AgentLimits契約に必要なUTC ISO 8601文字列へ変換します。"""
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def build_snapshot(windows: list[dict[str, Any]]) -> dict[str, Any]:
    """ウィンドウ配列からカスタム使用量スナップショットを組み立てます。"""
    return {
        "schemaVersion": 1,
        "provider": PROVIDER_ID,
        "fetchedAt": format_timestamp(datetime.now(timezone.utc)),
        "windows": windows,
    }


def is_token_near_expiry(expires_at: datetime | None) -> bool:
    """アクセストークンがREFRESH_BUFFER_SECONDS以内に失効するか判定します。"""
    if expires_at is None:
        return False
    return (expires_at - datetime.now(timezone.utc)).total_seconds() <= REFRESH_BUFFER_SECONDS


def refresh_access_token_via_agy() -> None:
    """`agy`の軽量サブコマンドを実行し、OAuthアクセストークンのリフレッシュを促します。"""
    run_command(AGY_REFRESH_COMMAND, timeout=AGY_REFRESH_TIMEOUT_SECONDS)


def fetch_quota_buckets() -> dict[str, dict[str, Any]]:
    """Keychainのアクセストークンを検証し、retrieveUserQuotaSummaryのバケット一覧を取得します。"""
    credentials = load_keychain_access_token()
    if credentials is None:
        raise AntigravityUsageError(
            "no Antigravity/agy Keychain credentials were found; sign in to Antigravity or run `agy` at least once"
        )
    access_token, expires_at = credentials

    if is_token_near_expiry(expires_at):
        refresh_access_token_via_agy()
        refreshed = load_keychain_access_token()
        if refreshed is not None:
            access_token, expires_at = refreshed
        if is_token_near_expiry(expires_at):
            raise AntigravityUsageError(
                "stored access token is expired and `agy` did not refresh it; "
                "open Antigravity or run `agy` again manually to refresh it"
            )

    buckets = extract_buckets(fetch_quota_summaries(access_token))
    five_hour_bucket = extract_gemini_five_hour_bucket(fetch_available_model_payloads(access_token))
    if five_hour_bucket is not None:
        merge_bucket(buckets, BUCKET_ID_BY_KIND["5h"], five_hour_bucket)
    return buckets


def main() -> None:
    """Antigravityの使用量を取得し、カスタムJSONを標準出力へ1件だけ出力します。"""
    windows = build_windows(fetch_quota_buckets())
    if not windows:
        raise AntigravityUsageError("no usable Gemini quota buckets were found in the quota API response")
    print(json.dumps(build_snapshot(windows), separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except AntigravityUsageError as error:
        fail(str(error))
