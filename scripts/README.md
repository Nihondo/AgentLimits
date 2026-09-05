# Sample scripts

This directory contains **samples**, not AgentLimits features or supported integrations.

## Cursor usage sample

`cursor_usage.py` is a sample script created by an AI coding agent using the repository-root [CUSTOM_USAGE_SCRIPT_GUIDE.md](../CUSTOM_USAGE_SCRIPT_GUIDE.md). It is provided only as a reference for creating a custom usage script.

## Antigravity usage sample

`antigravity_usage.py` is a sample script created by an AI coding agent using the repository-root [CUSTOM_USAGE_SCRIPT_GUIDE.md](../CUSTOM_USAGE_SCRIPT_GUIDE.md). It reads the OAuth access token Antigravity/`agy` stores in the macOS Keychain (read-only; it never performs an OAuth refresh, so an expired token requires reopening Antigravity or running `agy` once) and calls Cloud Code's `retrieveUserQuotaSummary` endpoint — the same one Antigravity's own "Models & Quota" panel uses — reporting the native Gemini 5-hour and weekly buckets (`gemini-5h`/`gemini-weekly`). This endpoint requires an Antigravity **standard/paid plan**: it was verified to return HTTP 403 "no valid license of this product" on a free-tier account, with no request-body workaround, so the script fails clearly with that explanation on a free-tier account rather than substituting a differently-scoped number. Antigravity's internal endpoints are unstable and undocumented; it is provided only as a reference for creating a custom usage script.
