# Custom Usage Script Authoring Guide

This document is written for an AI coding agent that is asked to build a "custom usage
script" for AgentLimits. It gives the agent everything needed to (1) interview the user
for the decisions only they can make, and (2) generate an executable that prints a
conforming JSON snapshot to stdout.

This guide is self-contained: it includes everything needed to write a conforming
script — the JSON contract, the execution contract, a decision checklist, and
ready-to-adapt examples.

## What AgentLimits runs, and how

A "custom usage service" in AgentLimits is any single executable file registered by the
user in Settings → Custom Usage. AgentLimits itself:

- Runs the executable directly (no shell, no arguments) on the app's own refresh
  interval (1-10 minutes, shared with built-in providers) plus on manual "test"/"refresh"
  triggers.
- Sets the working directory to the executable's own parent directory.
- Sets `PATH` to `/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:<inherited PATH>`.
- Enforces a **60 second timeout**, a **256 KiB stdout cap**, and a **64 KiB stderr cap**.
  Exceeding any of these is treated as a failure.
- Treats a non-zero exit code as failure and captures stderr (truncated to 64 KiB) as the
  error message shown in Settings.
- Requires stdout to be a single JSON document matching the contract below. Validation
  happens before anything is written to disk — a bad or missing script run **never**
  overwrites the last good snapshot; the widget keeps showing the last successful data.
- Never passes secrets to the script and never reads its source: whatever the script does
  to authenticate (env var, config file, keychain, cookie file, etc.) is entirely up to
  the script.

Because of this, the executable must be **fully self-contained**: any credentials, base
URLs, or config it needs must come from files/env it manages itself (e.g. a `.env` file
next to the script, a system keychain entry, an already-configured CLI tool like `gh` or
`aws`), not from arguments AgentLimits passes in — there are none.

The script can be written in any language as long as the file is directly executable
(`chmod +x`) with a correct shebang (`#!/usr/bin/env bash`, `#!/usr/bin/env python3`,
`#!/usr/bin/env node`, a compiled binary, etc.).

## Decisions only the user can make

Before generating anything, resolve these with the user. Do not guess silently — ask,
unless the answer is obvious from context (e.g. the user already pasted an API response).

| # | Decision | Why it matters |
|---|---|---|
| 1 | **Provider slug** — a short id like `cursor`, `openrouter`, `my-vps`. Must match `^[a-z0-9][a-z0-9_-]{0,62}$` (lowercase letters/digits/`_`/`-`, ≤63 chars, must not start with `_`/`-`). | Used as the JSON `provider` field, the registered service ID in AgentLimits, and the snapshot filename. Immutable once the service is registered in the app — pick something stable. |
| 2 | **Display name** — the human-readable name shown in Settings and the service picker. | Free text, can differ from the slug. |
| 3 | **Data source** — where usage numbers come from: a REST API (needs URL + auth method: bearer token, API key header, cookie, Basic auth), a local CLI tool already installed (e.g. parsing `some-cli usage --json`), a local file, etc. | Determines what the script actually does and what credentials setup is needed. |
| 4 | **Which usage window(s) apply**, out of 1-2 total: `5h`, `1w`, `1month`, or `custom` (anything that isn't semantically 5h/1week/1month — a rolling arbitrary window, a no-expiry credit balance, etc.). | Drives default label, default long-form title, and pacemaker division count. See table below. Only 1 or 2 windows are allowed, and kinds must be unique. |
| 5 | **Does each window have a hard reset time** (`resetAt` + `durationSeconds`), or is it open-ended (e.g. a lifetime credit balance with no reset)? | Without both `resetAt` and `durationSeconds`, the pacemaker ring/warning arrow is simply not shown for that window — this is a valid, common choice, not an error. |
| 6 | **Do you want a short label** (donut center / dashboard row) different from the `kind` default, and/or a **longer title** (medium-widget detail column, notification text)? | `label` overrides the short display *and* forces the pacemaker ring to a single undivided segment. `title` only affects the long-form heading and never touches the pacemaker ring. Leave both unset to use sensible per-`kind` defaults. |
| 7 | **Do you have `usedCount` / `limitCount`** (e.g. "425 / 1000 requests")? | Optional; shown only in the medium widget's detail column. Must be supplied as a pair or not at all. |
| 8 | **Auth/secrets storage** — env var file, macOS Keychain via `security`, a config file the script reads, or an already-authenticated CLI. | The script must read secrets itself; AgentLimits passes no arguments and no environment beyond a fixed `PATH`. Avoid hardcoding secrets directly in the script file if it will be shared or committed anywhere. |
| 9 | **Runtime dependencies** — is `curl`/`jq`/`python3`/`node`/etc. guaranteed to be on the user's Mac, or does the script need to check for and report a missing dependency clearly via stderr + non-zero exit? | AgentLimits does not install anything for the script; assume only what Homebrew/system provides on `PATH` as configured above. |

## The JSON contract the script must print to stdout

```json
{
  "schemaVersion": 1,
  "provider": "cursor",
  "fetchedAt": "2026-08-23T12:34:56Z",
  "windows": [
    {
      "kind": "5h",
      "label": "Fast Requests",
      "title": "High-speed request quota",
      "usedPercent": 42.5,
      "resetAt": "2026-08-23T15:00:00Z",
      "durationSeconds": 18000,
      "usedCount": 425,
      "limitCount": 1000
    },
    {
      "kind": "1w",
      "usedPercent": 68,
      "resetAt": "2026-08-30T00:00:00Z",
      "durationSeconds": 604800
    }
  ]
}
```

Print **only** this JSON to stdout (no logging mixed in). Send any diagnostic/debug
output to stderr instead — stderr is only surfaced to the user on failure.

### Top-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `schemaVersion` | Int | yes | Must be exactly `1`. |
| `provider` | String | yes | Must exactly match the provider slug registered in AgentLimits (decision #1). Mismatch is a validation error. |
| `fetchedAt` | ISO 8601 datetime, with timezone/offset | yes | Shown as the widget's "updated HH:mm" (falls back to `--:--` if over 24h stale). Use the real fetch time, not a cached one. |
| `windows` | Array, 1-2 items | yes | See below. Each `kind` must be unique within the array. |

### Per-window fields

| Field | Type | Required | If omitted | Notes |
|---|---|---|---|---|
| `kind` | `"5h"` \| `"1w"` \| `"1month"` \| `"custom"` | yes | — | See defaults table below. |
| `label` | String | no | falls back to `kind`'s default (`5h`/`1w`/`1mo`/`•`) | Short label for donut center + dashboard row. **Setting this forces the pacemaker ring to 1 undivided segment**, regardless of `durationSeconds`. |
| `title` | String | no | falls back to `label`, then to `kind`'s default long text | Long-form heading for the medium widget's detail column, notification settings section title, and notification body text. Independent of `label`; never affects pacemaker divisions. |
| `usedPercent` | Double, 0-100, finite | yes | — | Direct progress value; also drives the green/orange/red status color. |
| `resetAt` | ISO 8601 datetime with timezone | no | pacemaker disabled for this window | Must be paired with `durationSeconds` to enable the pacemaker ring; also shown as literal reset time text in the medium widget. |
| `durationSeconds` | Double, finite, > 0 | no | pacemaker disabled for this window | Length of the window in seconds. If provided it must be positive and finite (validation error otherwise) — but it is only used for pacemaker math if `resetAt` is also present. |
| `isPacemakerEnabled` | Bool | no | defaults to `true` | Set `false` to explicitly suppress the pacemaker ring/warning arrow even if `resetAt`+`durationSeconds` are present. |
| `usedCount` | Int ≥ 0 | no | not shown | Must be supplied together with `limitCount` or not at all (validation error if only one is present). Medium widget only, shown as `"425 / 1000"`. |
| `limitCount` | Int > 0 | no | not shown | See `usedCount`. |

### `kind` defaults

| `kind` | Default `label` | Default `title` (when both `label`/`title` omitted) | Pacemaker divisions (when `label` omitted) |
|---|---|---|---|
| `5h` | `5h` | "5-hour limit" | 5 (hourly) if `durationSeconds` ≈ 5h |
| `1w` | `1w` | "Weekly limit" | 7 (daily) if `durationSeconds` ≈ 7d |
| `1month` | `1mo` | "Monthly limit" | 1 (undivided) |
| `custom` | `•` | "Custom usage limit" | Determined by the actual `durationSeconds` value, not by the `kind` name — e.g. a `custom` window with a 5-hour `durationSeconds` still gets 5 divisions |

`custom` always sorts/displays last among the windows present. Use it for anything that
doesn't semantically map to a 5-hour, weekly, or monthly cycle — e.g. a rolling 30-day
window, a billing-cycle-anchored quota, or a no-reset lifetime credit pool.

### Validation the app performs before saving (know these to avoid silent failures)

- `schemaVersion` must be `1`.
- `provider` must equal the registered provider ID exactly.
- `windows` must have 1 or 2 entries; `kind` values must be unique.
- `usedPercent` must be finite and within `0...100`.
- If present, `durationSeconds` must be finite and `> 0`.
- `usedCount`/`limitCount` must both be present or both absent; if present, `usedCount >= 0` and `limitCount > 0`.
- Any decode/validation failure (bad JSON, wrong provider, out-of-range values, etc.)
  is rejected **before** touching the on-disk snapshot — the previous successful
  snapshot is preserved and the widget shows stale data rather than garbage.

## Recommended agent workflow

1. **Interview the user** using the checklist above. Do not proceed to code until you
   know: provider slug, display name, data source + auth, which window kind(s), whether
   reset/duration is available per window, and any label/title/count preferences.
2. **Confirm the exact upstream API/CLI contract** — actual request shape, auth header
   name, and the JSON path to the "used" and "limit" numbers. Ask the user for a sample
   response if unsure; do not guess field names.
3. **Write the executable** to compute `usedPercent` (and `resetAt`/`durationSeconds`
   when derivable) from that data, and print exactly one JSON document per the schema
   above.
4. **Make it robust**: non-zero exit + stderr message on any failure (network error,
   auth failure, unexpected response shape) rather than printing partial/invalid JSON.
   Do not let a transient upstream error produce a "successful" 0% or 100% snapshot.
5. **Test it exactly the way AgentLimits will invoke it**: no arguments, run from the
   script's own directory, with only the PATH prefix described above (i.e. don't rely on
   your interactive shell's extra PATH entries or aliases).
6. **Register it in AgentLimits**: Settings → Custom Usage → add a service with the
   agreed provider slug, display name, and the executable's path. Use the built-in "test"
   action to confirm a valid snapshot is produced before enabling auto-refresh.

## Example: Bash + curl + jq (single 5h window, API key auth)

```bash
#!/usr/bin/env bash
set -euo pipefail

PROVIDER="cursor"
API_KEY_FILE="$(dirname "$0")/.api_key"   # keep secrets out of the script body

if [[ ! -f "$API_KEY_FILE" ]]; then
  echo "missing API key file: $API_KEY_FILE" >&2
  exit 1
fi
API_KEY="$(<"$API_KEY_FILE")"

response="$(curl -fsS \
  -H "Authorization: Bearer ${API_KEY}" \
  "https://api.example.com/v1/usage")" || {
  echo "usage API request failed" >&2
  exit 1
}

used=$(jq -er '.used' <<<"$response")
limit=$(jq -er '.limit' <<<"$response")
reset_epoch=$(jq -er '.reset_at_unix' <<<"$response")

used_percent=$(awk -v u="$used" -v l="$limit" 'BEGIN { printf "%.2f", (l > 0) ? (u / l * 100) : 0 }')
reset_at=$(date -u -r "$reset_epoch" +"%Y-%m-%dT%H:%M:%SZ")
fetched_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg provider "$PROVIDER" \
  --arg fetchedAt "$fetched_at" \
  --arg resetAt "$reset_at" \
  --argjson usedPercent "$used_percent" \
  --argjson usedCount "$used" \
  --argjson limitCount "$limit" \
  '{
    schemaVersion: 1,
    provider: $provider,
    fetchedAt: $fetchedAt,
    windows: [
      {
        kind: "5h",
        usedPercent: $usedPercent,
        resetAt: $resetAt,
        durationSeconds: 18000,
        usedCount: $usedCount,
        limitCount: $limitCount
      }
    ]
  }'
```

## Example: Python (two windows, no reset time on the second)

```python
#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone

import requests  # must be available on the user's PATH/site-packages

PROVIDER = "my-service"

def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)

try:
    resp = requests.get(
        "https://api.example.com/usage",
        headers={"Authorization": "Bearer REPLACE_WITH_REAL_AUTH"},
        timeout=10,
    )
    resp.raise_for_status()
    data = resp.json()
except Exception as exc:
    fail(f"usage fetch failed: {exc}")

now = datetime.now(timezone.utc)

snapshot = {
    "schemaVersion": 1,
    "provider": PROVIDER,
    "fetchedAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "windows": [
        {
            "kind": "5h",
            "usedPercent": round(data["fast"]["used"] / data["fast"]["limit"] * 100, 2),
            "resetAt": data["fast"]["reset_at"],  # already ISO 8601 with TZ
            "durationSeconds": 18000,
        },
        {
            # no reset date available -> pacemaker simply won't show for this window
            "kind": "custom",
            "label": "Credits",
            "usedPercent": round(data["credits"]["used"] / data["credits"]["limit"] * 100, 2),
            "usedCount": data["credits"]["used"],
            "limitCount": data["credits"]["limit"],
        },
    ],
}

print(json.dumps(snapshot))
```

## Quick failure checklist (things that silently keep the old snapshot on screen)

- Wrong `provider` value (must match the registered slug exactly).
- `schemaVersion` missing or not `1`.
- Duplicate `kind` values, or 0/3+ windows.
- `usedPercent` outside `0-100`, `NaN`, or infinite.
- `durationSeconds` present but `<= 0` or non-finite.
- Only one of `usedCount`/`limitCount` set.
- Script exits non-zero, hangs past 60s, or writes more than 256 KiB to stdout /
  64 KiB to stderr.
- Non-UTF8 or non-JSON bytes mixed into stdout (e.g. accidental `echo` debug lines).
