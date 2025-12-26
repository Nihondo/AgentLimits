# AgentLimits

**In Development**

A macOS Sonoma+ menu bar app and Notification Center widgets that display ChatGPT Codex / Claude Code usage limits (5-hour and weekly windows).

![](./images/agentlimit_sample.png)

## Latest Version Download
Please download the latest version from here: [Download](https://github.com/Nihondo/AgentLimits/releases/latest/download/AgentLimits.zip)

## Features

### Usage Monitoring
- Sign in to each service in the in-app WKWebView (switch between Codex/Claude)
- Fetch usage data from Internal APIs:
  - Codex: `https://chatgpt.com/backend-api/wham/usage` (JSON)
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage` (JSON)
- Store provider-specific snapshots in App Group `group.com.(your domain).agentlimit`
- Separate widgets for Codex and Claude
- Auto refresh: every minute while the app is running (logged-in services only)

### Wake Up (CLI Scheduler)
- Automatically run CLI commands (`codex exec "Hello"` / `claude -p "Hello"`) at scheduled hours
- Implemented via LaunchAgent (macOS standard scheduled execution)
- Per-provider schedule configuration
- Support for additional arguments (e.g., `--model="haiku"`)
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
4. Switch between Codex/Claude at the top of the window
5. Log in to each service in the WebView at the bottom
6. Use the menu bar "Display Mode" to switch used/remaining
7. "Refresh Now" updates only the currently selected service

### Wake Up Settings
1. Select "Wake up Settings..." from the menu bar
2. Choose provider (Codex / Claude Code)
3. Enable "Enable schedule"
4. Select hours to run (0-23)
5. Use "Test Now" to verify CLI execution

### Threshold Notification Settings
1. Select "Threshold Notification Settings..." from the menu bar
2. Request notification permission (first time only)
3. Choose provider (Codex / Claude Code)
4. Configure threshold for 5h/weekly limits separately

## Displayed Data
- 5-hour usage (%) or remaining (%)
- Weekly usage (%) or remaining (%)
- Last updated (relative time)
- Display mode is set from the menu bar and shared across app/widgets

## Notes
- Fetching depends on internal APIs and may break if they change.
- Widget refresh frequency may be throttled by the OS.
- Threshold notification requires notification permission.
