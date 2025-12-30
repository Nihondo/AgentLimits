import Foundation

enum WidgetRelativeTimeFormatter {
    static func makeRelativeUpdatedText(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return "time.withinMinute".widgetLocalized()
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "time.minutesAgo".widgetLocalized(minutes)
        }
        let hours = minutes / 60
        if hours < 24 {
            return "time.hoursAgo".widgetLocalized(hours)
        }
        let days = hours / 24
        return "time.daysAgo".widgetLocalized(days)
    }
}
