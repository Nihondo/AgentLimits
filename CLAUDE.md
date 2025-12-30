# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AgentLimits is a macOS Sonoma+ menu bar app with WidgetKit widgets that display usage limits (Codex/Claude) and ccusage token usage (today/this week/this month). The app embeds WKWebView for service login and fetches usage data from internal backend APIs. ccusage token usage is fetched via CLI and stored as snapshots for widgets.

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
3. `UsageViewModel` manages auto-refresh (configurable 1-10 minutes) and per-provider state
4. `UsageSnapshotStore` persists usage snapshots as JSON under App Group container
5. `CCUsageFetcher` runs CLI to fetch token usage:
   - Codex: `npx -y @ccusage/codex@latest daily`
   - Claude: `npx -y ccusage@latest daily`
6. `TokenUsageViewModel` manages auto-refresh (configurable 1-10 minutes) and snapshot persistence
7. Widgets read their respective snapshot files (no network access)
8. `ThresholdNotificationManager` checks usage against thresholds and sends notifications
9. Menu bar label displays real-time usage percentages for enabled providers

### Key Components

| File | Purpose |
|------|---------|
| `AgentLimits/App/AgentLimitsApp.swift` | Main app entry, menu bar UI, deep link handling |
| `AgentLimits/App/AppSharedState.swift` | Shared app state for menu bar and settings window |
| `AgentLimits/App/SettingsTabView.swift` | Tab-based settings UI (Usage, ccusage, Wake Up, Notification) |
| `AgentLimits/App/LanguageManager.swift` | Language settings management (Japanese/English/System) |
| `AgentLimits/App/LoginItemManager.swift` | Login item (start at login) management |
| `AgentLimits/Usage/CodexUsageFetcher.swift` | Codex API + JS token extraction |
| `AgentLimits/Usage/ClaudeUsageFetcher.swift` | Claude API + JS org ID extraction |
| `AgentLimits/Usage/UsageViewModel.swift` | Usage limits state, auto-refresh, per-provider tracking, threshold check |
| `AgentLimits/Usage/UsageDisplayModeStore.swift` | Display mode persistence and snapshot conversion |
| `AgentLimits/Usage/AppUsageModels.swift` | App-only display mode + localized errors |
| `AgentLimits/Usage/ContentView.swift` | Usage limits settings UI with WebView |
| `AgentLimits/Usage/WebViewStore.swift` | WKWebView lifecycle, page-ready detection |
| `AgentLimits/Usage/WebViewScriptRunner.swift` | JavaScript injection executor |
| `AgentLimits/Usage/UsageWebViewPool.swift` | Per-provider WebViewStore management |
| `AgentLimits/CCUsage/TokenUsageViewModel.swift` | ccusage state, auto-refresh, snapshot persistence |
| `AgentLimits/CCUsage/CCUsageFetcher.swift` | CLI execution + parsing for ccusage |
| `AgentLimits/CCUsage/CCUsageSettingsView.swift` | ccusage settings UI |
| `AgentLimitsShared/UsageModels.swift` | Shared usage models/store and helpers (`UsageSnapshot`, `UsageWindow`, `UsageSnapshotStore`, `UsageProvider`, display mode + status/percent helpers) |
| `AgentLimitsShared/TokenUsageModels.swift` | Shared token usage models/store and helpers (`TokenUsageSnapshot`, `TokenUsageProvider`, MonthStartDateResolver, CCUsageLinks) |
| `AgentLimitsShared/TokenUsageFormatting.swift` | Shared cost/token formatting for ccusage |
| `AgentLimitsWidget/AgentLimitsWidget.swift` | Usage limits widget TimelineProvider and donut gauge UI |
| `AgentLimitsWidget/TokenUsageWidget.swift` | ccusage token usage widget TimelineProvider and rows UI |
| `AgentLimitsWidget/AgentLimitsWidgetBundle.swift` | Widget bundle registration |
| `AgentLimitsWidget/WidgetUsageModels.swift` | Widget error localization (bridges shared resolver to widget strings) |
| `AgentLimitsWidget/WidgetLanguageHelper.swift` | Widget language helper |
| `AgentLimitsWidget/WidgetRelativeTimeFormatter.swift` | Relative time formatting for widgets |
| `AgentLimits/WakeUp/WakeUpScheduler.swift` | LaunchAgent-based CLI scheduler for starting 5h sessions |
| `AgentLimits/WakeUp/WakeUpSettingsView.swift` | Wake Up schedule configuration UI |
| `AgentLimits/Notification/ThresholdNotificationManager.swift` | Usage threshold notification logic |
| `AgentLimits/Notification/ThresholdNotificationSettings.swift` | Per-provider, per-window threshold settings model |
| `AgentLimits/Notification/ThresholdNotificationStore.swift` | Threshold settings persistence |
| `AgentLimits/Notification/ThresholdSettingsView.swift` | Threshold notification settings UI |

### Features

#### Menu Bar Status Display
- Real-time usage percentage display in menu bar for enabled providers
- Two-line layout (line 1: provider name, line 2: `X% / Y%` for 5h/weekly)
- Color-coded status:
  - Used mode: green (<70%), orange (70-89%), red (≥90%)
  - Remaining mode: green (>=31%), orange (11-30%), red (<=10%)
- Per-provider toggle (Codex/Claude separately)
- Responds to display mode changes (used/remaining)
- Uses ImageRenderer to generate dynamic images that honor light/dark mode

#### Usage Monitoring
- Sign in to each service in the in-app WKWebView (Codex/Claude)
- Auto refresh interval is configurable (1-10 minutes)
- Display mode (used/remaining) shared across app + widgets
- Color-coded percentage display in widgets based on usage level and display mode

#### Token Usage (ccusage)
- CLI-based fetch and parsing for Codex/Claude
- Separate widgets for ccusage token usage
- Auto refresh interval is configurable (1-10 minutes)
- Widget tap opens `https://ccusage.com/` via app deep link

#### Wake Up (LaunchAgent-based CLI Scheduler)
- Schedules CLI commands (`codex exec --skip-git-repo-check "hello"` / `claude -p "hello"`) at user-defined hours
- Creates LaunchAgent plist files in `~/Library/LaunchAgents/`
- Logs CLI output to `/tmp/agentlimit-wakeup-*.log`
- Per-provider schedule with additional CLI arguments support
- Test execution from settings UI

#### Threshold Notification
- Sends system notifications when usage exceeds configured threshold
- Per-provider settings (Codex / Claude separately)
- Per-window settings (5h / weekly separately)
- Default threshold: 90%
- Duplicate prevention: notifies only once per reset cycle

### Shared Data Model

`AgentLimitsShared/UsageModels.swift` defines the shared usage model and snapshot store. App/widget add target-specific extensions in `AgentLimits/Usage/AppUsageModels.swift` and `AgentLimitsWidget/WidgetUsageModels.swift`. The `UsageSnapshot` struct contains:
- `provider`: `.chatgptCodex` or `.claudeCode`
- `primaryWindow` / `secondaryWindow`: `UsageWindow` with `usedPercent`, `resetAt`, `limitWindowSeconds`
- `fetchedAt`: Date

`AgentLimitsShared/TokenUsageModels.swift` defines token usage snapshots:
- `provider`: `.codex` or `.claude`
- `today` / `thisWeek` / `thisMonth`: `TokenUsagePeriod` with `costUSD`, `totalTokens`
- `fetchedAt`: Date

### Storage Paths (App Group: `group.com.dmng.agentlimit`)

```
~/Library/Group Containers/group.com.dmng.agentlimit/Library/Application Support/AgentLimit/
├── usage_snapshot.json           # Codex usage limits
├── usage_snapshot_claude.json    # Claude usage limits
├── token_usage_codex.json        # ccusage Codex
└── token_usage_claude.json       # ccusage Claude
```

### UserDefaults Keys

| Key | Purpose |
|-----|---------|
| `usage_display_mode` | Display mode (used% / remaining%) |
| `usage_display_mode_cached` | Cached display mode used to convert stored snapshots (also shared via App Group for widgets) |
| `menu_bar_status_codex_enabled` | Menu bar Codex status display toggle |
| `menu_bar_status_claude_enabled` | Menu bar Claude status display toggle |
| `wake_up_schedules` | Wake Up schedules (JSON array) |
| `threshold_notification_settings` | Threshold settings (JSON array) |
| `app_language` | Language preference (App Group shared) |
| `usage_refresh_interval_minutes` | Usage limits auto-refresh interval (minutes) |
| `token_usage_refresh_interval_minutes` | ccusage auto-refresh interval (minutes) |
| `ccusage_settings` | ccusage settings (JSON) |

### Widget Kinds

- `AgentLimitWidget` - Codex usage limits widget
- `AgentLimitWidgetClaude` - Claude usage limits widget
- `TokenUsageWidgetCodex` - ccusage Codex widget
- `TokenUsageWidgetClaude` - ccusage Claude widget

### Entitlements

- **App**: App Groups + Network Client
- **Widget**: App Groups only (reads cached data)

## Notes

- Keep `README.md` in English
- Keep `README_ja.md` in Japanese
- Keep `AGENTS.md` and `CLAUDE.md` in English
- Backend APIs are undocumented and may change without notice
- Widget refresh frequency may be throttled by the OS
