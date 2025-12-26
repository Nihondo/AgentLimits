# AgentLimits Contributor Notes

## Purpose
- AgentLimits is a macOS Sonoma+ app with WidgetKit widgets that display ChatGPT Codex and Claude Code usage limits.
- The app logs in via an embedded WKWebView and fetches:
  - Codex: `https://chatgpt.com/backend-api/wham/usage`
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage`
- Each widget reads a provider-specific snapshot from the App Group storage and only renders UI.

## Key Features

### Usage Monitoring
- Auto refresh: every 60 seconds while the app is running
- Display mode: used% or remaining% (set from menu bar, shared across app + widgets)
- Language preference: stored in App Group under `app_language`

### Wake Up (CLI Scheduler)
- Schedules CLI commands at user-defined hours via LaunchAgent
- Commands: `codex exec --skip-git-repo-check "hello"` / `claude -p "hello"`
- LaunchAgent plist files: `~/Library/LaunchAgents/com.dmng.agentlimit.wakeup-*.plist`
- Logs: `/tmp/agentlimit-wakeup-*.log`
- Per-provider schedule with additional CLI arguments support

### Threshold Notification
- Sends system notifications (UNUserNotificationCenter) when usage exceeds threshold
- Per-provider settings (Codex / Claude separately)
- Per-window settings (5h / weekly separately)
- Default threshold: 90%
- Duplicate prevention: notifies only once per reset cycle (tracked by `lastNotifiedResetAt`)

## Key Decisions
- App Group ID: `group.com.(your domain).agentlimit`
- Widget kinds: `AgentLimitWidget` (Codex), `AgentLimitWidgetClaude` (Claude)
- Wake Up uses `launchctl bootstrap/bootout` (modern macOS API)
- Threshold notification requires user permission (requested via settings UI)

## Structure
- `AgentLimits/` (macOS app)
  - `Notification/` (threshold notification components)
  - `WakeUpScheduler.swift`, `WakeUpSettingsView.swift` (Wake Up feature)
- `AgentLimitsShared/` (shared models/store for app + widget)
- `AgentLimitsWidget/` (widget extension)

## Storage

### App Group Container
```
~/Library/Group Containers/group.com.(your domain).agentlimit/Library/Application Support/AgentLimit/
├── usage_snapshot.json        # Codex snapshot
└── usage_snapshot_claude.json # Claude snapshot
```

### UserDefaults Keys
| Key | Purpose |
|-----|---------|
| `usage_display_mode` | Display mode (used% / remaining%) |
| `wake_up_schedules` | Wake Up schedules (JSON array) |
| `threshold_notification_settings` | Threshold settings (JSON array) |
| `app_language` | Language preference (App Group shared) |

## Update Workflow
1. App saves a `UsageSnapshot` as JSON in the App Group container
2. Widgets load their respective snapshots and render two gauges (5h and weekly)
3. `ThresholdNotificationManager.checkThresholdsIfNeeded()` is called after each successful fetch
4. If usage >= threshold and not already notified for this reset cycle, notification is sent

## Notes
- Keep this file in English
- Keep `README.md` in Japanese
- Keep `README_ja.md` in Japanese
- Keep `CLAUDE.md` in English
- Set the Development Team ID via `Configurations/DevelopmentTeam.local.xcconfig` (gitignored). The shared `Configurations/DevelopmentTeam.xcconfig` includes it optionally.
