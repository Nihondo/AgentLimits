import Foundation

enum WidgetUpdateTimeFormatter {
    /// Cached DateFormatter for HH:mm format (creating formatters is expensive)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Number of seconds in 24 hours
    private static let secondsPerDay: TimeInterval = 86400

    /// Formats a date as HH:mm, or "--:--" if more than 24 hours ago
    static func formatUpdateTime(since date: Date, now: Date = Date()) -> String {
        let elapsedSeconds = now.timeIntervalSince(date)
        if elapsedSeconds >= secondsPerDay {
            return "--:--"
        }
        return timeFormatter.string(from: date)
    }
}
