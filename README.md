# AgentLimits

**In Development**

A macOS Sonoma+ menu bar app and Notification Center widgets that show ChatGPT Codex / Claude Code usage limits (5-hour and weekly windows) and ccusage token usage.

![](./images/agentlimit_sample.png)

## Latest Version Download
Please download the latest version from here: [Download](https://github.com/Nihondo/AgentLimits/releases/latest/download/AgentLimits.zip)

## Features

### Usage Monitoring (Codex / Claude)
- Sign in to each service in the in-app WKWebView (switch between Codex/Claude)
- Fetch usage data from internal APIs:
  - Codex: `https://chatgpt.com/backend-api/wham/usage` (JSON)
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage` (JSON)
- Store provider-specific snapshots in App Group `group.com.dmng.agentlimit`
- Separate widgets for Codex and Claude
- Auto refresh: configurable 1-10 minutes (menu next to provider selector)
- Display mode (used/remaining) is switched from the menu bar

### ccusage Token Usage
- Fetch via CLI and store snapshots
  - Codex: `npx -y @ccusage/codex@latest daily`
  - Claude: `npx -y ccusage@latest daily`
- Shows today/this week/this month tokens and cost
- Separate widgets for Codex and Claude token usage
- Auto refresh: configurable 1-10 minutes (menu next to provider selector in ccusage settings)
- Widget tap opens `https://ccusage.com/`

### Wake Up (CLI Scheduler)
- Automatically run CLI commands (`codex exec "Hello"` / `claude -p "Hello"`) at scheduled hours
- Implemented via LaunchAgent (macOS standard scheduled execution)
- Per-provider schedule configuration
- Supports additional arguments (e.g., `--model="haiku"`)
- **What is this feature for?** Often, a session starts at 9 AM, is used up by 12 PM, leaving the user unable to do anything until 2 PM. In such cases, if the session starts at 7 AM, it will be reset by 12 PM, allowing it to be used again.

### Threshold Notification
- Display system notification when usage exceeds threshold
- Per-provider settings (Codex / Claude separately)
- Per-window settings (5h / weekly separately)
- Default threshold: 90%
- Notifies only once per reset cycle (duplicate prevention)

## Basic Usage
1. Run the AgentLimits app.
2. Add the widget in Notification Center.
3. Select "AgentLimits Settings..." from the menu bar icon.
4. Switch between Codex/Claude at the top of the window.
5. Choose refresh interval (1-10 minutes) from the menu on the right.
6. Log in to each service in the WebView at the bottom.
7. Use the menu bar "Display Mode" to switch used/remaining.
8. "Refresh Now" updates only the currently selected service.

### ccusage Settings
1. Select "ccusage Settings..." from the menu bar.
2. Choose provider (Codex / Claude).
3. Choose refresh interval (1-10 minutes) from the menu on the right.
4. Enable periodic fetch.
5. Use "Test Now" to verify CLI execution.

### Wake Up Settings
1. Select "Wake up Settings..." from the menu bar.
2. Choose provider (Codex / Claude Code).
3. Enable schedule.
4. Select hours to run (0-23).
5. Use "Test Now" to verify CLI execution.

### Threshold Notification Settings
1. Select "Threshold Notification Settings..." from the menu bar.
2. Request notification permission (first time only).
3. Choose provider (Codex / Claude Code).
4. Configure threshold for 5h/weekly limits separately.

## Displayed Data
- Usage widgets:
  - 5-hour usage (%) or remaining (%)
  - Weekly usage (%) or remaining (%)
  - Last updated (relative time)
- ccusage widgets:
  - Today/this week/this month cost (USD)
  - Today/this week/this month tokens
  - Last updated (relative time)

## Notes
- Fetching depends on internal APIs and may break if they change.
- ccusage CLI output changes may break parsing.
- Widget refresh frequency may be throttled by the OS.
- Threshold notifications require permission.
- The CLI is launched via zsh, and the PATH for the codex, claude, and npx commands must be set in the zsh environment.
- You may experience login failures with Claude, requiring multiple attempts.