# AgentLimits

**In Development**

AgentLimits is a macOS Sonoma+ menu bar app with Notification Center widgets. It shows usage limits for ChatGPT Codex / Claude Code (5-hour and weekly windows), GitHub Copilot (monthly premium requests), and ccusage token usage.

![](./images/agentlimit_sample.png)

## Download
Download the latest build: [Download](https://github.com/Nihondo/AgentLimits/releases/latest/download/AgentLimits.zip)

## Quick Start (First-Time Setup)
1. Run AgentLimits.
2. Add widgets in Notification Center.
3. Open **AgentLimits Settings...** from the menu bar.
4. In **Usage**, choose Codex, Claude Code, or Copilot, set refresh interval (1–10 minutes), open the bottom login panel (`▲`), then sign in.
5. Use the menu bar **Display Mode** to switch Used/Remaining, and **Refresh Now** for manual updates.

## What It Tracks
- **Usage limits (Codex / Claude Code):** 5-hour and weekly usage via internal APIs.
  - Codex: `https://chatgpt.com/backend-api/wham/usage`
  - Claude Code: `https://claude.ai/api/organizations/{orgId}/usage`
- **Usage limits (GitHub Copilot):** Monthly premium interaction quota via entitlement API.
  - Copilot: `https://github.com/github-copilot/chat/entitlement`
- **Token usage (ccusage):** daily/weekly/monthly tokens and cost via CLI.
  - Codex: `npx -y @ccusage/codex@latest daily`
  - Claude Code: `npx -y ccusage@latest daily`
- **Premium request usage (Copilot):** daily premium request count and cost via WebView.
  - API: `https://github.com/settings/billing/usage_table` (fetched automatically with Copilot usage)

## Menu Bar Display
- Two-line layout per provider in the icon area
  - Line 1: provider name
  - Line 2: `X% / Y%` (5-hour / weekly)
  - For Copilot: `X%` (monthly)
- Display mode: **Used** or **Remaining** (shared across app and widgets)
- Status colors are based on pacemaker comparison when available (colors are configurable in **Notification** settings)
- Status colors in the menu bar are automatically darkened or lightened to match the current menu bar text color.
- Pacemaker indicator: optionally shows `<used>%↑` when over pace
- Toggle icon visibility per provider in **Usage** settings
- Provider display order (Codex / Claude Code / Copilot) is configurable in **Usage** settings (**Display Order**)

### Menu Dashboard
When you open the menu bar menu, a dashboard appears at the top showing per-provider usage at a glance:
- Header: provider name · remaining time (5h window) · days until weekly reset
- **Usage bar**: linear progress bar color-coded by usage level; when pacemaker is exceeded, the bar is segmented (green → orange → red) matching the widget donut ring behavior
- **Pacemaker bar**: divided into time segments (5h: 5 segments, weekly: 7 segments) with gaps, matching the widget inner ring
- Clicking a dashboard row opens the provider's usage page in the browser
- Dashboard visibility is configurable per provider in **Usage** settings (**Show dashboard in menu**)
- Menu also includes: **Display Mode**, **Language** (System/Japanese/English), **Wake Up → Run Now**, **Start app at login**, and **Check for Updates...**

![](./images/agentlimits_menu.png)


## Pacemaker
Pacemaker shows a time-based usage benchmark to help you stay on track.

- **Calculation**: Elapsed percentage of the usage window (e.g., 50% = halfway through the 5h or weekly window)
- **Comparison**: Green = on track or ahead, Orange = slightly over pace, Red = 10%+ over pace
- **Menu Bar**: Shows `<used>% (<pacemaker>)%` with toggleable pacemaker value display (**Pacemaker** settings)
- **Widget**: Outer ring = actual usage, inner ring = pacemaker percentage (shown when pacemaker data is available)
  - When usage exceeds pacemaker in **used mode only**, the outer ring is segmented and color-coded (green → orange → red) to show warning/danger zones (toggleable in **Pacemaker** settings, enabled by default)
- **Thresholds**: Warning/danger delta thresholds are configurable in **Pacemaker** settings
- **Colors**: Pacemaker ring/text colors are configurable in **Pacemaker** settings

## Widgets
### Usage Widgets (Codex / Claude Code)
- Dual donut gauge: 5-hour and weekly windows side by side
- Color-coded percentage based on usage level and display mode
- Update time shown as `HH:mm` (or `--:--` if older than 24h)

### Usage Widget (GitHub Copilot)
- Single centered donut gauge: monthly premium interaction quota
- Pacemaker inner ring divided into weekly segments (4–5 segments based on billing period)
- Center label: `1mo`
- Color-coded percentage based on usage level and display mode
- Update time shown as `HH:mm` (or `--:--` if older than 24h)

### Token Usage Widgets (Codex / Claude Code)
- **Small:** today / this week / this month summary (cost + tokens)
- **Medium:** summary + GitHub-style heatmap
  - 7 rows (Sun–Sat) × 4–6 columns (weeks)
  - 5 levels by quartile distribution
  - Weekday labels (Mon, Wed, Fri)
  - Desktop pinned mode support (accented / grayscale)
- Widget tap action is configurable (default opens `https://ccusage.com/`)

### Premium Requests Usage Widget (GitHub Copilot)
- **Small:** today / this week / this month summary (cost + premium requests)
- **Medium:** summary + GitHub-style heatmap
- Data is fetched automatically when Copilot usage is refreshed (via WebView, no CLI required)
- Widget tap action is configurable (default opens `https://ccusage.com/`)

## Settings Guide
### Usage
1. Open **Usage**.
2. Select Codex, Claude Code, or Copilot.
3. Choose refresh interval (1–10 minutes).
4. Toggle **Show in menu bar** to show the usage percentage in the icon area.
5. Toggle **Show dashboard in menu** to show/hide the provider's row in the menu dashboard.
6. Drag rows in **Display Order** to change the order of providers in the menu bar icon and dashboard.
7. Click the bottom login bar (`▲`) to expand the embedded WebView panel.
8. Sign in via the embedded WebView (chatgpt.com / claude.ai / github.com).
9. Use **Clear Data** to remove login data and website storage if sign-in gets stuck.

### ccusage
1. Open **ccusage**.
2. Select provider (Codex / Claude Code).
3. Choose refresh interval (1–10 minutes).
4. Enable periodic fetch and set additional CLI args if needed.
5. Use **Test Now** to verify CLI execution.
6. For Copilot: billing data is fetched automatically when Copilot usage is refreshed — just enable the toggle.

### Wake Up
1. Open **Wake Up**.
2. Select provider (Codex / Claude Code). Note: Copilot is not supported.
3. Enable schedule.
4. Choose hours to run (0–23).
5. Use **Test Now** to verify CLI execution.

### Notification
1. Open **Notification**.
2. Request notification permission (first time only).
3. Select provider (Codex / Claude Code / Copilot).
4. Configure thresholds for each window (5-hour/weekly for Codex/Claude Code, monthly for Copilot).
5. Adjust usage colors (donut + status colors) if needed.

### Pacemaker
1. Open **Pacemaker**.
2. Toggle the menu bar pacemaker value display.
3. Toggle the widget ring warning segments (color-coded segments when exceeding pacemaker).
4. Adjust pacemaker warning/danger deltas.
5. Customize pacemaker ring/text colors.

### Advanced
1. Open **Advanced**.
2. Set full paths for `codex`, `claude`, `npx` if needed (blank = resolve via PATH).
3. Review PATH resolution results.
4. Choose widget tap action (open website / refresh data).
5. Copy the bundled status line script path if needed.

## Wake Up (CLI Scheduler)
- Runs scheduled commands:
  - `codex exec --skip-git-repo-check "hello"`
  - `claude -p "hello"`
- LaunchAgent plist: `~/Library/LaunchAgents/com.dmng.agentlimit.wakeup-*.plist`
- Logs: `/tmp/agentlimit-wakeup-*.log`
- Additional CLI arguments are supported per provider.

## Claude Code Status Line Script
![](./images/agentlimits_statusline_sample.png)
- Bundled script for Claude Code status line integration (path shown in **Advanced → Bundled Scripts**)
- Reads Claude Code usage snapshot + App Group settings (display mode, language, thresholds, colors)
- Outputs a single line with 5-hour/weekly usage, reset times, and update time
- Options: `-ja`, `-en`, `-r` (remaining), `-u` (used), `-p` (pacemaker), `-i` (usage + pacemaker inline), `-d` (debug)
- Requires `jq` (`brew install jq`)

## Advanced: Storage (App Group)
Snapshots are stored in the App Group container:
```
~/Library/Group Containers/group.com.dmng.agentlimit/Library/Application Support/AgentLimit/
├── usage_snapshot.json
├── usage_snapshot_claude.json
├── usage_snapshot_copilot.json
├── token_usage_codex.json
├── token_usage_claude.json
└── token_usage_copilot.json
```

## Notes / Troubleshooting
- Internal APIs may change without notice.
- ccusage output changes may break parsing.
- Widget refresh can be throttled by macOS.
- Threshold notifications require permission.
- CLI execution uses the **user login shell** and prefixes PATH with `/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH`.
- Full-path overrides in **Advanced** take precedence.
- Claude Code logins may require multiple attempts.
- The Claude Code status line script requires `jq`.
- Settings window minimum height is `620` to keep the bottom login panel visible.

## Automatic Updates

AgentLimits uses [Sparkle](https://sparkle-project.org/) for automatic updates.

- **Startup check**: Checks for updates automatically when the app launches.
- **Scheduled check**: Rechecks every 24 hours in the background.
- **Manual check**: Open the **Update** tab in Settings or choose **Check for Updates...** from the menu bar menu.
- Updates are downloaded and installed with one click after you confirm.
