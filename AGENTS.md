# AgentLimits Contributor Notes

## Purpose
- AgentLimits is a macOS Sonoma+ app with WidgetKit widgets that display ChatGPT Codex and Claude Code usage limits.
- The app logs in via an embedded WKWebView and fetches:
  - Codex: `https://chatgpt.com/backend-api/wham/usage`
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage`
- Each widget reads a provider-specific snapshot from the App Group storage and only renders UI.

## Key decisions
- App Group ID: `group.com.(your domain).agentlimit`
- Auto refresh: every 60 seconds while the app is running.
- Widget kinds: `AgentLimitWidget` (Codex), `AgentLimitWidgetClaude` (Claude)
- Display mode (used vs remaining) is set from the menu bar and shared across app + widgets.
- Language preference is stored in App Group under `app_language`.

## Structure
- `AgentLimits/` (macOS app)
- `AgentLimitsShared/` (shared models/store for app + widget)
- `AgentLimitsWidget/` (widget extension)

## Update workflow
- App saves a `UsageSnapshot` as JSON in the App Group container:
- Codex: `~/Library/Group Containers/group.com.(your domain).agentlimit/Library/Application Support/AgentLimit/usage_snapshot.json`
- Claude: `~/Library/Group Containers/group.com.(your domain).agentlimit/Library/Application Support/AgentLimit/usage_snapshot_claude.json`
- Widgets load their respective snapshots and render two gauges (5 hours and weekly).

## Notes
- Keep this file in English.
- Keep `README_ja.md` in Japanese.
- Keep `README.md` in English.
