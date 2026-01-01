# AgentLimits

**In Development**

AgentLimits is a macOS Sonoma+ menu bar app with Notification Center widgets that display ChatGPT Codex / Claude Code usage limits (5-hour and weekly windows) and ccusage token usage.

![](./images/agentlimit_sample.png)

## Latest Version Download
Download the latest build here: [Download](https://github.com/Nihondo/AgentLimits/releases/latest/download/AgentLimits.zip)

## Features

### Menu Bar Status Display
- Real-time usage percentage in the menu bar
- Two-line layout per provider (Codex/Claude)
  - Line 1: provider name
  - Line 2: `X% / Y%` (5-hour / weekly)
- Status coloring by usage rate
  - Used mode: normal / warning / danger
  - Remaining mode: normal / warning / danger (thresholds inverted)
- Per-provider toggle in Usage settings
- Responds to display mode changes (used/remaining)
- Renders dynamic images via `ImageRenderer`
- Usage rate colors (normal/warning/danger) are customizable in Advanced Settings

### Usage Monitoring (Codex / Claude)
- Sign in via in-app WKWebView (switch between Codex/Claude)
- Fetch usage data from internal APIs:
  - Codex: `https://chatgpt.com/backend-api/wham/usage`
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage`
- Provider snapshots are saved to App Group `group.com.dmng.agentlimit`
- Separate widgets for Codex and Claude
- Auto refresh: configurable 1–10 minutes
- Display mode is switched from the menu bar
- Widget percentages are color-coded by usage level

### ccusage Token Usage
- Fetch via CLI and store snapshots
  - Codex: `npx -y @ccusage/codex@latest daily`
  - Claude: `npx -y ccusage@latest daily`
- Shows today/this week/this month tokens and cost
- Separate widgets for Codex and Claude token usage
- **Small widget**: Summary (today/week/month)
- **Medium widget**: Summary + GitHub-style heatmap for the current month
  - 7 rows (Sun–Sat) × 4–6 columns (weeks)
  - 5 levels by quartile distribution
  - Weekday labels (Mon, Wed, Fri)
  - Desktop pinned mode support (accented/grayscale)
- Auto refresh: configurable 1–10 minutes
- Widget tap opens `https://ccusage.com/`

### Wake Up (CLI Scheduler)
- Runs CLI commands at scheduled hours
  - `codex exec --skip-git-repo-check "hello"`
  - `claude -p "hello"`
- Implemented via LaunchAgent
- Per-provider schedule and additional args support
- LaunchAgent plist: `~/Library/LaunchAgents/com.dmng.agentlimit.wakeup-*.plist`
- Logs: `/tmp/agentlimit-wakeup-*.log`

### Threshold Notification
- System notification when usage rate exceeds threshold
- Per-provider (Codex/Claude) and per-window (5h/weekly) settings
- Default threshold: 90%
- Notifies once per reset cycle

### Advanced Settings (CLI Paths / Colors)
- Set full paths for `codex`, `claude`, and `npx` (optional)
  - Empty = resolve via PATH
  - Resolution results are shown in the UI
- Customize donut chart color
- Customize usage rate colors (normal/warning/danger)
  - Applies to menu bar + widgets
- “Use usage-based colors” for donuts
- “Reset to Defaults” restores color settings

## Basic Usage
1. Run AgentLimits.
2. Add the widget in Notification Center.
3. Choose “AgentLimits Settings...” from the menu bar.
4. Switch between Codex/Claude.
5. Select refresh interval (1–10 minutes).
6. Log in via WebView.
7. Use menu bar “Display Mode” to switch usage rate/remaining rate.
8. “Refresh Now” updates the selected service.

## Settings Screens

### Usage Settings
1. Open the **Usage** tab.
2. Select Codex or Claude.
3. Choose refresh interval (1–10 minutes).
4. Toggle “Show in menu bar” per provider.
5. Log in via the embedded WebView.

### Menu Bar Status
1. Enable “Show in menu bar” for each provider you want displayed.
2. The menu bar shows `X% / Y%` for 5-hour and weekly windows.

### ccusage Settings
1. Open the **ccusage** tab.
2. Select provider (Codex / Claude).
3. Choose refresh interval (1–10 minutes).
4. Enable periodic fetch.
5. Use “Test Now” to verify CLI execution.

### Wake Up Settings
1. Open the **Wake Up** tab.
2. Select provider (Codex / Claude Code).
3. Enable schedule.
4. Select hours to run (0–23).
5. Use “Test Now” to verify CLI execution.

### Threshold Notification Settings
1. Open the **Notification** tab.
2. Request notification permission (first time only).
3. Select provider (Codex / Claude Code).
4. Configure thresholds for 5-hour and weekly windows.

### Advanced Settings
1. Open the **Advanced** tab.
2. Set full paths for `codex`, `claude`, and `npx` if needed.
3. Review PATH resolution results.
4. Customize donut chart color and usage status colors.
5. Enable “Use usage-based colors” for donuts if desired.
6. Use “Reset to Defaults” to restore colors.

## Notes
- Internal APIs may change without notice.
- ccusage CLI output changes may break parsing.
- Widget refresh can be throttled by macOS.
- Threshold notifications require permission.
- CLI execution uses the **user login shell**.
- PATH is prefixed with `"/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"`.
- If full paths are specified in Advanced Settings, those paths are used.
- Claude logins may require multiple attempts.
