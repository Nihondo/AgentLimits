# AgentLimits Contributor Notes

## Purpose
- AgentLimits is a macOS Sonoma+ menu bar app with WidgetKit widgets that display usage limits (Codex/Claude) and ccusage token usage.
- The app logs in via an embedded WKWebView and fetches:
  - Codex: `https://chatgpt.com/backend-api/wham/usage`
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage`
- ccusage token usage is fetched via CLI:
  - Codex: `npx -y @ccusage/codex@latest daily`
  - Claude: `npx -y ccusage@latest daily`
- Each widget reads a provider-specific snapshot from the App Group storage and only renders UI.
- Menu bar displays real-time usage percentages for enabled providers.

## Key Features

### Menu Bar Status Display
- Real-time usage percentage display in menu bar (5h/weekly)
- Two-line layout (line 1: provider name, line 2: `X% / Y%`)
- Color-coded status:
  - Used mode: normal / warning / danger
  - Remaining mode: normal / warning / danger (thresholds inverted)
- Per-provider toggle (Codex/Claude separately)
- Responds to display mode changes (used/remaining)
- Colors are customizable from Advanced Settings

### Usage Monitoring
- Auto refresh: configurable 1-10 minutes while the app is running (usage limits)
- Display mode: used% or remaining% (set from menu bar, shared across app + widgets)
- Language preference: stored in App Group under `app_language`
- Color-coded percentage display in widgets based on usage level and display mode

### Token Usage (ccusage)
- Periodic CLI fetch (Codex/Claude) and snapshot persistence
- Separate widgets for Codex/Claude token usage (today/this week/this month)
- **Small widget**: Usage summary only
- **Medium widget**: Usage summary + GitHub-style heatmap
  - 7 rows (Sun-Sat) × 4-6 columns (weeks)
  - 5-level color intensity based on quartile distribution
  - Weekday labels (Mon, Wed, Fri) displayed
  - Desktop pinned mode support (opacity-based white colors)
- Auto refresh: configurable 1-10 minutes (ccusage settings screen)
- Widget tap opens `https://ccusage.com/` via app deep link

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

### Advanced Settings (CLI Paths / Colors)
- Full path overrides for `codex`, `claude`, `npx`
- Resolved PATH results shown in UI
- Donut ring color for widget
- Usage status colors (normal/warning/danger) for menu bar + widget
- Option to color donuts by usage status
- Reset to defaults

## Key Decisions
- App Group ID: `group.com.dmng.agentlimit`
- Widget kinds:
  - `AgentLimitWidget` (Codex usage limits)
  - `AgentLimitWidgetClaude` (Claude usage limits)
  - `TokenUsageWidgetCodex` (ccusage Codex)
  - `TokenUsageWidgetClaude` (ccusage Claude)
- Wake Up uses `launchctl bootstrap/bootout` (modern macOS API)
- Threshold notification requires user permission (requested via settings UI)
- Menu bar status uses ImageRenderer for dynamic template images
- CLI execution uses the user login shell and prefixes PATH with `/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH`
- Full-path overrides (Advanced Settings) take precedence

## Structure
- `AgentLimits/` (macOS app)
  - `App/` (app entry, shared state, language/login item management, settings tabs)
  - `Usage/` (usage limits UI, WebView, fetchers, display mode store)
  - `CCUsage/` (ccusage UI, fetcher, view model)
  - `WakeUp/` (Wake Up feature)
  - `Notification/` (threshold notification components)
- `AgentLimitsShared/` (shared models/store + display mode/status helpers and ccusage links)
  - `UsageColorSettings.swift` (usage color persistence)
- `AgentLimitsWidget/` (widget extension)
  - `TokenUsageWidget.swift` (small + medium widget with heatmap)
  - `HeatmapView.swift` (heatmap grid rendering)
  - `HeatmapColors.swift` (5-level color scheme + accented mode)
  - `HeatmapLevelResolver.swift` (quartile-based level calculation)

## Storage

### App Group Container
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
| `usage_display_mode_cached` | Cached display mode used to convert stored snapshots (shared via App Group for widgets) |
| `menu_bar_status_codex_enabled` | Menu bar Codex status display toggle |
| `menu_bar_status_claude_enabled` | Menu bar Claude status display toggle |
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

## Update Workflow
1. App saves a `UsageSnapshot` and `TokenUsageSnapshot` as JSON in the App Group container
2. Widgets load their respective snapshots and render gauges (usage limits) or rows (token usage)
3. `ThresholdNotificationManager.checkThresholdsIfNeeded()` is called after each successful usage fetch
4. If usage >= threshold and not already notified for this reset cycle, notification is sent
5. Menu bar label observes `UsageViewModel` and updates display in real-time

## Notes
- Keep this file in English
- Keep `README.md` in English
- Keep `README_ja.md` in Japanese
- Keep `CLAUDE.md` in English
- Set the Development Team ID via `Configurations/DevelopmentTeam.local.xcconfig` (gitignored). The shared `Configurations/DevelopmentTeam.xcconfig` includes it optionally.
