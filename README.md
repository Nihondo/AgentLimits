# AgentLimits

**In Development**

A macOS Sonoma+ menu bar app and Notification Center widgets that display ChatGPT Codex / Claude Code usage limits (5-hour and weekly windows).

![](./images/agentlimit_sample.png)

## Overview
- Login: sign in to each service in the in-app WKWebView (switch between Codex/Claude)
- Fetch:
  - Codex: `https://chatgpt.com/backend-api/wham/usage` (JSON)
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage` (JSON)
- Share: store provider-specific snapshots in App Group `group.com.(your domain).agentlimit`
- Widgets: separate widgets for Codex and Claude
- Shared models: common models/store live under `AgentLimitsShared/`
- Auto refresh: every minute while the app is running (logged-in services only)

## Usage
1. Open `AgentLimits.xcodeproj` in Xcode
2. Run the macOS target
3. Select “Open Settings Window” from the menu bar icon
4. Switch between Codex/Claude at the top of the window
5. Log in to each service in the WebView at the bottom
6. Use the menu bar “Display Mode” to switch used/remaining
7. “Refresh Now” updates only the currently selected service
8. In Apple Developer Identifiers, enable the same App Group ID (`group.com.(your domain).agentlimit`) for both bundle IDs (app + widget)

## Displayed Data
- 5-hour usage (%) or remaining (%)
- Weekly usage (%) or remaining (%)
- Last updated (relative time)
- Display mode is set from the menu bar and shared across app/widgets

## Distribution (Developer ID)

To distribute the app outside the Mac App Store with notarization:

1. Select the **AgentLimits Release** scheme in Xcode
2. Choose **Product → Archive** to create an archive
3. In Organizer, select **Distribute App → Developer ID**
4. Notarization will be performed automatically
5. Export the notarized `.app` or `.dmg`

### Build Settings (pre-configured)
- Hardened Runtime: Enabled
- App Sandbox: Enabled
- Debug Symbols: dSYM (for crash reports)
- Widget Extension: Included in archive

## Notes
- Fetching depends on internal APIs and may break if they change.
- Widget refresh frequency may be throttled by the OS.
