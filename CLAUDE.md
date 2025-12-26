# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AgentLimits is a macOS Sonoma+ menu bar app with WidgetKit widgets that display ChatGPT Codex and Claude Code usage limits (5-hour and weekly windows). The app embeds WKWebView for service login and fetches usage data from internal backend APIs.

## Build Commands

```bash
# Open in Xcode (recommended)
xed AgentLimits.xcodeproj

# Build from CLI
xcodebuild -scheme AgentLimits -destination 'platform=macOS'

# Run tests
xcodebuild test -scheme AgentLimits -destination 'platform=macOS'
```

## Architecture

### Data Flow
1. User logs into service (chatgpt.com or claude.ai) via WKWebView
2. `*UsageFetcher` executes JavaScript to extract auth token/org ID, then fetches usage API:
   - Codex: `https://chatgpt.com/backend-api/wham/usage`
   - Claude: `https://claude.ai/api/organizations/{orgId}/usage`
3. `UsageViewModel` manages auto-refresh (60s interval) and per-provider state
4. `UsageSnapshotStore` persists snapshots as JSON under App Group container
5. Widgets read their respective snapshot files (no network access)
6. `ThresholdNotificationManager` checks usage against thresholds and sends notifications

### Key Components

| File | Purpose |
|------|---------|
| `CodexUsageFetcher.swift` | Codex API + JS token extraction |
| `ClaudeUsageFetcher.swift` | Claude API + JS org ID extraction |
| `UsageViewModel.swift` | State management, auto-refresh, per-provider tracking, threshold check |
| `AgentLimitsShared/UsageModels.swift` | Shared models/store (`UsageSnapshot`, `UsageWindow`, `UsageSnapshotStore`, `UsageProvider`) |
| `AppUsageModels.swift` | App-only display mode + localized errors |
| `WidgetUsageModels.swift` | Widget-only localized errors |
| `WebViewStore.swift` | WKWebView lifecycle, page-ready detection |
| `UsageWebViewPool.swift` | Per-provider WebViewStore management |
| `AppSharedState.swift` | Shared app state for menu bar and settings window |
| `AgentLimitsWidget.swift` | Widget TimelineProvider and donut gauge UI |
| `WakeUpScheduler.swift` | LaunchAgent-based CLI scheduler for starting 5h sessions |
| `WakeUpSettingsView.swift` | Wake Up schedule configuration UI |
| `Notification/ThresholdNotificationManager.swift` | Usage threshold notification logic |
| `Notification/ThresholdNotificationSettings.swift` | Per-provider, per-window threshold settings model |
| `Notification/ThresholdNotificationStore.swift` | Threshold settings persistence |
| `Notification/ThresholdSettingsView.swift` | Threshold notification settings UI |

### Features

#### Wake Up (LaunchAgent-based CLI Scheduler)
- Schedules CLI commands (`codex exec` / `claude -p`) at user-defined hours
- Creates LaunchAgent plist files in `~/Library/LaunchAgents/`
- Per-provider schedule with additional CLI arguments support
- Test execution from settings UI

#### Threshold Notification
- Sends system notifications when usage exceeds configured threshold
- Per-provider settings (Codex / Claude separately)
- Per-window settings (5h / weekly separately)
- Default threshold: 90%
- Duplicate prevention: notifies only once per reset cycle

### Shared Data Model

`AgentLimitsShared/UsageModels.swift` defines the shared data model and snapshot store. App/widget add target-specific extensions in `AppUsageModels.swift` and `WidgetUsageModels.swift`. The `UsageSnapshot` struct contains:
- `provider`: `.chatgptCodex` or `.claudeCode`
- `primaryWindow` / `secondaryWindow`: `UsageWindow` with `usedPercent`, `resetAt`, `limitWindowSeconds`
- `fetchedAt`: Date

### Storage Paths (App Group: `group.com.(your domain).agentlimit`)

```
~/Library/Group Containers/group.com.(your domain).agentlimit/Library/Application Support/AgentLimit/
├── usage_snapshot.json        # Codex
└── usage_snapshot_claude.json # Claude
```

### UserDefaults Keys

| Key | Purpose |
|-----|---------|
| `usage_display_mode` | Display mode (used% / remaining%) |
| `wake_up_schedules` | Wake Up schedules (JSON array) |
| `threshold_notification_settings` | Threshold settings (JSON array) |

### Widget Kinds

- `AgentLimitWidget` - Codex widget
- `AgentLimitWidgetClaude` - Claude widget

### Entitlements

- **App**: App Groups + Network Client
- **Widget**: App Groups only (reads cached data)

## Notes

- Keep `README_ja.md` in Japanese
- Keep `README.md` in English
- Keep `AGENTS.md` and `CLAUDE.md` in English
- Backend APIs are undocumented and may change without notice
- Display mode (used% vs remaining%) is set from the menu bar and shared between app and widgets via cached snapshots
- Wake Up uses `launchctl bootstrap/bootout` for modern macOS LaunchAgent management
