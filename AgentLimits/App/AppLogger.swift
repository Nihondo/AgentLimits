import OSLog

/// Centralized logger extension for AgentLimits app.
/// Use these loggers for structured logging with Console.app integration.
///
/// Usage:
/// ```swift
/// Logger.wakeup.info("Installing plist at \(path)")
/// Logger.notification.error("Failed to send: \(error.localizedDescription)")
/// ```
///
/// Log collection (for user support):
/// ```bash
/// log show --predicate 'subsystem == "com.dmng.agentlimit"' --last 1h
/// log collect --device --last 1h --output ~/Desktop/agentlimits.logarchive
/// ```
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.dmng.agentlimit"

    /// Wake Up feature: LaunchAgent management and CLI execution
    static let wakeup = Logger(subsystem: subsystem, category: "wakeup")

    /// Threshold notification: usage alerts and notification delivery
    static let notification = Logger(subsystem: subsystem, category: "notification")

    /// Usage display: snapshot storage and display mode
    static let usage = Logger(subsystem: subsystem, category: "usage")

    /// App settings: login items, preferences
    static let app = Logger(subsystem: subsystem, category: "app")

    /// ccusage: token usage fetching and processing
    static let ccusage = Logger(subsystem: subsystem, category: "ccusage")
}
