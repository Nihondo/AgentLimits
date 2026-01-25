# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AgentLimits is a macOS Sonoma+ menu bar app with WidgetKit widgets that display usage limits (Codex/Claude Code) and ccusage token usage (today/this week/this month). The app embeds WKWebView for service login and fetches usage data from internal backend APIs. ccusage token usage is fetched via CLI and stored as snapshots for widgets.

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
   - Claude Code: `https://claude.ai/api/organizations/{orgId}/usage`
3. `UsageViewModel` manages auto-refresh (configurable 1-10 minutes) and per-provider state
4. `UsageSnapshotStore` persists usage snapshots as JSON under App Group container
5. `CCUsageFetcher` runs CLI to fetch token usage:
   - Codex: `npx -y @ccusage/codex@latest daily`
   - Claude Code: `npx -y ccusage@latest daily`
6. `TokenUsageViewModel` manages auto-refresh (configurable 1-10 minutes) and snapshot persistence
7. Widgets read their respective snapshot files (no network access)
8. `ThresholdNotificationManager` checks usage against thresholds and sends notifications
9. Menu bar label displays real-time usage percentages for enabled providers
10. Bundled Claude Code status line script reads snapshots + App Group settings for CLI display

### Key Components

| File | Purpose |
|------|---------|
| `AgentLimits/App/AgentLimitsApp.swift` | Main app entry, menu bar UI, deep link handling |
| `AgentLimits/App/AppSharedState.swift` | Shared app state for menu bar and settings window |
| `AgentLimits/App/SettingsTabView.swift` | Tab-based settings UI (Usage, ccusage, Wake Up, Notification, Advanced) |
| `AgentLimits/App/CLICommandSettingsView.swift` | Advanced Settings UI (CLI paths + scripts + widget tap action) |
| `AgentLimits/App/LanguageManager.swift` | Language settings management (Japanese/English/System) |
| `AgentLimits/App/LoginItemManager.swift` | Login item (start at login) management |
| `AgentLimits/App/AppLogger.swift` | Application-wide logging utility |
| `AgentLimits/App/AutoRefreshCoordinator.swift` | Auto-refresh cycle coordination |
| `AgentLimits/App/ShellExecutor.swift` | Shell command execution utility |
| `AgentLimits/Usage/CodexUsageFetcher.swift` | Codex API + JS token extraction |
| `AgentLimits/Usage/ClaudeUsageFetcher.swift` | Claude API + JS org ID extraction |
| `AgentLimits/Usage/UsageViewModel.swift` | Usage limits state, auto-refresh, per-provider tracking, threshold check |
| `AgentLimits/Usage/ProviderStateManager.swift` | Per-provider state management (Codex/Claude Code independent tracking) |
| `AgentLimits/Usage/UsageDisplayModeStore.swift` | Display mode persistence and snapshot conversion |
| `AgentLimits/Usage/AppUsageModels.swift` | App-only display mode + localized errors |
| `AgentLimits/Usage/ContentView.swift` | Usage limits settings UI with WebView |
| `AgentLimits/Usage/WebViewStore.swift` | WKWebView lifecycle, page-ready detection |
| `AgentLimits/Usage/WebViewScriptRunner.swift` | JavaScript injection executor |
| `AgentLimits/Usage/UsageWebViewPool.swift` | Per-provider WebViewStore management |
| `AgentLimits/CCUsage/TokenUsageViewModel.swift` | ccusage state, auto-refresh, snapshot persistence |
| `AgentLimits/CCUsage/CCUsageFetcher.swift` | CLI execution + parsing for ccusage |
| `AgentLimits/CCUsage/CCUsageSettingsView.swift` | ccusage settings UI |
| `AgentLimitsShared/UsageModels.swift` | Shared usage models/store and helpers |
| `AgentLimitsShared/UsageColorSettings.swift` | Usage color persistence (menu bar + widgets) |
| `AgentLimitsShared/TokenUsageModels.swift` | Shared token usage models/store and helpers |
| `AgentLimitsShared/TokenUsageFormatting.swift` | Shared cost/token formatting for ccusage |
| `AgentLimitsShared/WidgetTapActionSettings.swift` | Widget tap action settings (open website / refresh data) |
| `AgentLimitsWidget/AgentLimitsWidget.swift` | Usage limits widget TimelineProvider and donut gauge UI |
| `AgentLimitsWidget/TokenUsageWidget.swift` | ccusage token usage widget TimelineProvider and rows UI (small + medium with heatmap) |
| `AgentLimitsWidget/HeatmapView.swift` | Heatmap grid view for medium widget (7 rows × 4-6 columns) |
| `AgentLimitsWidget/HeatmapColors.swift` | 5-level color scheme (GitHub-style) + accented mode support |
| `AgentLimitsWidget/HeatmapLevelResolver.swift` | Quartile-based level calculation for heatmap colors |
| `AgentLimitsWidget/AgentLimitsWidgetBundle.swift` | Widget bundle registration |
| `AgentLimitsWidget/WidgetUsageModels.swift` | Widget error localization (bridges shared resolver to widget strings) |
| `AgentLimitsWidget/WidgetLanguageHelper.swift` | Widget language helper |
| `AgentLimitsWidget/WidgetUpdateTimeFormatter.swift` | Update time formatting (HH:mm or --:-- if >24h ago) |
| `AgentLimits/WakeUp/WakeUpScheduler.swift` | LaunchAgent-based CLI scheduler for starting 5h sessions |
| `AgentLimits/WakeUp/WakeUpSettingsView.swift` | Wake Up schedule configuration UI |
| `AgentLimits/Notification/ThresholdNotificationManager.swift` | Usage threshold notification logic |
| `AgentLimits/Notification/ThresholdNotificationSettings.swift` | Per-provider, per-window threshold settings model |
| `AgentLimits/Notification/ThresholdNotificationStore.swift` | Threshold settings persistence |
| `AgentLimits/Notification/ThresholdSettingsView.swift` | Threshold notification settings UI (thresholds + usage colors) |
| `AgentLimits/Pacemaker/PacemakerSettingsView.swift` | Pacemaker settings UI (menu bar toggle + thresholds + colors) |
| `AgentLimits/Scripts/agentlimits_statusline_claude.sh` | Claude Code status line script (reads App Group snapshots) |

### Features

#### Menu Bar Status Display
- Real-time usage percentage display in menu bar for enabled providers
- Two-line layout (line 1: provider name, line 2: `X% / Y%` for 5h/weekly)
- Color-coded status based on pacemaker comparison when available (otherwise secondary)
- Per-provider toggle (Codex/Claude Code separately)
- Responds to display mode changes (used/remaining)
- Pacemaker value: shows `<used>% (<pacemaker>)%` with toggleable pacemaker value display (Pacemaker settings)
- Status colors are customizable from Notification settings
- Menu bar menu includes Display Mode, Language selection, Wake Up → Run Now, and Start app at login

#### Pacemaker Mode
- Time-based usage benchmark that calculates what percentage of the window has elapsed
- Compares actual usage against elapsed time to determine if user is on track
- Status levels based on difference (usedPercent - pacemakerPercent):
  - Green: at or below pacemaker (on track)
  - Orange: exceeds pacemaker (slight excess, default threshold: 0%)
  - Danger: 10%+ ahead of pacemaker (significant excess, default threshold: 10%)
- Widget shows dual rings when pacemaker data is available: outer = actual usage, inner = pacemaker percentage
- Menu bar shows both values with configurable colors
- Thresholds and pacemaker colors are configurable in Pacemaker settings (warning/danger delta)

#### Usage Monitoring
- Sign in to each service in the in-app WKWebView (Codex/Claude Code)
- Auto refresh interval is configurable (1-10 minutes)
- Display mode (used/remaining) shared across app + widgets
- Color-coded percentage display in widgets based on usage level and display mode
- Widget tap action configurable: open website or refresh data (Advanced Settings)
- Usage screen includes **Clear Data** to remove embedded browser login data and website storage

#### Token Usage (ccusage)
- CLI-based fetch and parsing for Codex/Claude Code
- Separate widgets for ccusage token usage (small and medium sizes)
- Per-provider enable/disable with additional CLI arguments support
- **Small widget**: Usage summary (today/week/month cost and tokens)
- **Medium widget**: Usage summary + GitHub-style heatmap
  - Layout: 7 rows (Sun-Sat) × 4-6 columns (weeks of current month)
  - Color levels: 5 levels based on quartile distribution (GitHub contributions style)
  - Weekday labels: Mon, Wed, Fri displayed on left side
  - Desktop pinned mode: Uses opacity-based white colors for accented rendering
- Auto refresh interval is configurable (1-10 minutes)
- Widget tap action configurable: open website or refresh data (Advanced Settings)

#### Wake Up (LaunchAgent-based CLI Scheduler)
- Schedules CLI commands (`codex exec --skip-git-repo-check "hello"` / `claude -p "hello"`) at user-defined hours
- Creates LaunchAgent plist files in `~/Library/LaunchAgents/`
- Logs CLI output to `/tmp/agentlimit-wakeup-*.log`
- Per-provider schedule with additional CLI arguments support
- Test execution from settings UI

#### Threshold Notification
- Sends system notifications when usage exceeds configured threshold
- Per-provider settings (Codex / Claude Code separately)
- Per-window settings (5h / weekly separately)
- Default threshold: 90%
- Duplicate prevention: notifies only once per reset cycle
- Usage color settings (donut + status colors) live in Notification settings

#### Advanced Settings (CLI Paths / Scripts / Widget Tap)
- Full path overrides for `codex`, `claude`, `npx`
- PATH resolution results shown in UI
- Bundled status line script path shown with copy action
- Widget tap action: open website (default) or refresh data

#### Claude Code Status Line Script
- Bundled script for Claude Code status line integration
- Reads Claude Code usage snapshot and App Group settings (display mode, language, thresholds, colors)
- Outputs a single line with 5h/weekly usage, reset times, and update time
- Supports overrides: `-ja`, `-en`, `-r` (remaining), `-u` (used), `-p` (pacemaker), `-i` (usage + pacemaker inline), `-d` (debug)
- Requires `jq`

### Shared Data Model

`AgentLimitsShared/UsageModels.swift` defines the shared usage model and snapshot store. App/widget add target-specific extensions in `AgentLimits/Usage/AppUsageModels.swift` and `AgentLimitsWidget/WidgetUsageModels.swift`.

`AgentLimitsShared/TokenUsageModels.swift` defines token usage snapshots:
- `provider`: `.codex` or `.claude`
- `today` / `thisWeek` / `thisMonth`: `TokenUsagePeriod` with `costUSD`, `totalTokens`
- `dailyUsage`: `[DailyUsageEntry]` - Daily usage entries for heatmap (ISO8601 date string + totalTokens)
- `fetchedAt`: Date

### Storage Paths (App Group: `group.com.dmng.agentlimit`)

```
~/Library/Group Containers/group.com.dmng.agentlimit/Library/Application Support/AgentLimit/
├── usage_snapshot.json           # Codex usage limits
├── usage_snapshot_claude.json    # Claude Code usage limits
├── token_usage_codex.json        # ccusage Codex
└── token_usage_claude.json       # ccusage Claude
```

### UserDefaults Keys

| Key | Purpose |
|-----|---------|
| `usage_display_mode` | Display mode (used% / remaining% / pacemaker) |
| `usage_display_mode_cached` | Cached display mode used to convert stored snapshots (also shared via App Group for widgets) |
| `menu_bar_status_codex_enabled` | Menu bar Codex status display toggle |
| `menu_bar_status_claude_enabled` | Menu bar Claude Code status display toggle |
| `wake_up_schedules` | Wake Up schedules (JSON array) |
| `threshold_notification_settings` | Threshold settings (JSON array) |
| `app_language` | Language preference (App Group shared) |
| `usage_refresh_interval_minutes` | Usage limits auto-refresh interval (minutes) |
| `token_usage_refresh_interval_minutes` | ccusage auto-refresh interval (minutes) |
| `ccusage_settings` | ccusage settings (JSON) |
| `cli_path_codex` | Full path override for codex |
| `cli_path_claude` | Full path override for claude |
| `cli_path_npx` | Full path override for npx |
| `usage_color_donut` | Donut ring color (widget) |
| `usage_color_donut_use_status` | Donut uses usage status colors |
| `usage_color_green` | Usage normal color |
| `usage_color_orange` | Usage warning color |
| `usage_color_red` | Usage danger color |
| `usage_color_threshold_revision` | Revision bump for threshold updates |
| `usage_color_threshold_warning_{provider}_{window}` | Warning threshold used for usage status colors |
| `usage_color_threshold_danger_{provider}_{window}` | Danger threshold used for usage status colors |
| `widget_tap_action` | Widget tap action (openWebsite / refreshData) |
| `menu_bar_show_pacemaker_value` | Menu bar pacemaker value display toggle |
| `usage_color_pacemaker_ring` | Pacemaker ring color (widget) |
| `usage_color_pacemaker_text` | Pacemaker text color (menu bar) |
| `pacemaker_warning_delta` | Pacemaker mode warning threshold delta (default: 0%) |
| `pacemaker_danger_delta` | Pacemaker mode danger threshold delta (default: 10%) |

### Widget Kinds

- `AgentLimitWidget` - Codex usage limits widget
- `AgentLimitWidgetClaude` - Claude Code usage limits widget
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
- CLI execution uses the user login shell and prefixes PATH with `/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH`
- Full-path overrides from Advanced Settings take precedence
- Usage status color thresholds are synced from notification thresholds per provider/window
- Claude Code status line script requires `jq`
