// MARK: - AgentLimitsWidget.swift
// WidgetKit extension showing usage donuts for Codex and Claude Code.
// Builds timelines from App Group snapshots persisted by the main app.

import SwiftUI
import WidgetKit

/// Timeline provider that reads snapshots from shared App Group storage
struct UsageTimelineProvider: TimelineProvider {
    let provider: UsageProvider

    /// Lightweight placeholder used in widget gallery
    func placeholder(in context: Context) -> UsageEntry {
        // Use placeholder snapshot to render gallery preview.
        UsageEntry(date: Date(), snapshot: placeholderSnapshot, provider: provider)
    }

    /// Provides a current snapshot for widget previews or the widget itself
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            // Preview mode uses placeholder data for fast rendering.
            completion(UsageEntry(date: Date(), snapshot: placeholderSnapshot, provider: provider))
            return
        }
        // Load latest snapshot from App Group storage.
        let snapshot = UsageSnapshotStore.shared.loadSnapshot(for: provider)
        completion(UsageEntry(date: Date(), snapshot: snapshot, provider: provider))
    }

    /// Builds a timeline refreshing every minute, matching app auto-refresh
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // Read snapshot and schedule the next refresh based on shared interval.
        let snapshot = UsageSnapshotStore.shared.loadSnapshot(for: provider)
        let entry = UsageEntry(date: Date(), snapshot: snapshot, provider: provider)
        let nextUpdate = Date().addingTimeInterval(UsageRefreshConfig.refreshIntervalSeconds)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    /// Static placeholder snapshot to render gauges in the gallery
    private var placeholderSnapshot: UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            fetchedAt: Date(),
            primaryWindow: UsageWindow(
                kind: .primary,
                usedPercent: 42,
                resetAt: Date().addingTimeInterval(60 * 30),
                limitWindowSeconds: 60 * 60 * 5
            ),
            secondaryWindow: UsageWindow(
                kind: .secondary,
                usedPercent: 73,
                resetAt: Date().addingTimeInterval(60 * 60 * 24),
                limitWindowSeconds: 60 * 60 * 24 * 7
            )
        )
    }
}

/// Timeline entry containing the latest usage snapshot
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let provider: UsageProvider
}

/// Main widget view that renders donuts and detail labels
struct AgentLimitsWidgetEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot

        VStack(alignment: .leading, spacing: 6) {
            Text(entry.provider.displayName)
                .font(.headline)
                .padding(.top,8)

            if let snapshot {
                switch family {
                case .systemSmall:
                    GeometryReader { proxy in
                        let spacing: CGFloat = 12
                        let targetDonutSize: CGFloat = 66
                        let availableDonutSize = max(0, (proxy.size.width - spacing) / 2)
                        let donutSize = min(targetDonutSize, availableDonutSize)
                        let columnHeight = donutSize + 30
                        UsageDonutRow(
                            primaryWindow: snapshot.primaryWindow,
                            secondaryWindow: snapshot.secondaryWindow,
                            donutSize: donutSize,
                            spacing: spacing,
                            columnHeight: columnHeight
                        )
                        .frame(height: columnHeight, alignment: .center)
                    }
                    .frame(height: 100)
                    .padding(.top, 6)
                case .systemMedium:
                    GeometryReader { proxy in
                        let detailWidth: CGFloat = 170
                        let spacing: CGFloat = 12
                        let targetDonutSize: CGFloat = 66
                        let leftWidth = max(0, proxy.size.width - detailWidth - spacing)
                        let availableDonutSize = max(0, (leftWidth - spacing) / 2)
                        let donutSize = min(targetDonutSize, availableDonutSize)
                        let columnHeight = donutSize + 30
                        HStack(alignment: .center, spacing: 0) {
                            UsageDonutRow(
                                primaryWindow: snapshot.primaryWindow,
                                secondaryWindow: snapshot.secondaryWindow,
                                donutSize: donutSize,
                                spacing: spacing,
                                columnHeight: columnHeight
                            )
                            .frame(width: leftWidth, alignment: .leading)

                            Spacer(minLength: 0)

                            UsageDetailColumnView(
                                primaryWindow: snapshot.primaryWindow,
                                secondaryWindow: snapshot.secondaryWindow
                            )
                            .frame(width: detailWidth, alignment: .trailing)
                            .padding(.trailing, 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: max(columnHeight, 96), alignment: .center)
                    }
                    .frame(height: 100)
                    .padding(.top, 6)
                default:
                    UsageDonutRow(
                        primaryWindow: snapshot.primaryWindow,
                        secondaryWindow: snapshot.secondaryWindow,
                        donutSize: 44,
                        spacing: 16,
                        columnHeight: 70
                    )
                    .padding(.top, 0)
                }
                HStack(spacing: 6) {
                    Text("widget.updated".widgetLocalized())
                    Text(WidgetRelativeTimeFormatter.makeRelativeUpdatedText(since: snapshot.fetchedAt))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, -6)
            } else {
                Text("widget.notFetched".widgetLocalized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("widget.pleaseLogin".widgetLocalized())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .widgetURL(entry.provider.widgetDeepLinkURL)
    }

}

private func usageConfiguration(for provider: UsageProvider) -> some WidgetConfiguration {
    StaticConfiguration(kind: provider.widgetKind, provider: UsageTimelineProvider(provider: provider)) { entry in
        AgentLimitsWidgetEntryView(entry: entry)
            .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName(provider.displayName)
    .description("widget.description".widgetLocalized())
    .supportedFamilies([.systemSmall, .systemMedium])
}

struct CodexUsageLimitWidget: Widget {
    var body: some WidgetConfiguration {
        usageConfiguration(for: .chatgptCodex)
    }
}

struct ClaudeUsageLimitWidget: Widget {
    var body: some WidgetConfiguration {
        usageConfiguration(for: .claudeCode)
    }
}

private struct UsageDonutRow: View {
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
    let donutSize: CGFloat
    let spacing: CGFloat
    let columnHeight: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            UsageDonutColumnView(
                centerLabel: "5h",
                window: primaryWindow,
                donutSize: donutSize,
                columnHeight: columnHeight
            )
            UsageDonutColumnView(
                centerLabel: "1w",
                window: secondaryWindow,
                donutSize: donutSize,
                columnHeight: columnHeight
            )
        }
    }
}

private struct UsageDonutColumnView: View {
    let centerLabel: String
    let window: UsageWindow?
    let donutSize: CGFloat
    let columnHeight: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            UsageDonutView(centerLabel: centerLabel, usedPercent: window?.usedPercent, size: donutSize)
            Text(percentText)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundColor(statusColor)
        }
        .frame(height: columnHeight, alignment: .center)
    }

    private var percentText: String {
        return UsagePercentFormatter.formatPercentText(window?.usedPercent)
    }

    private var statusColor: Color {
        WidgetUsageColorResolver.statusColor(for: window)
    }
}

private struct UsageDonutView: View {
    let centerLabel: String
    let usedPercent: Double?
    let size: CGFloat

    private var progress: Double {
        let value = (usedPercent ?? 0) / 100
        return min(max(value, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .foregroundStyle(.tint)
            Text(centerLabel)
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(centerLabel)
        .accessibilityValue(UsagePercentFormatter.formatPercentText(usedPercent, placeholder: "0%"))
    }
}

private struct UsageDetailColumnView: View {
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageDetailSectionView(
                title: "widget.5hourLimit".widgetLocalized(),
                window: primaryWindow,
                showRelative: true,
                showDateTime: false
            )
            UsageDetailSectionView(
                title: "widget.weeklyLimit".widgetLocalized(),
                window: secondaryWindow,
                showRelative: false,
                showDateTime: true
            )
        }
    }
}

private struct UsageDetailSectionView: View {
    let title: String
    let window: UsageWindow?
    let showRelative: Bool
    let showDateTime: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text("  " + "widget.reset".widgetLocalized())
                .font(.headline)
                .monospacedDigit()
            Text("  "+resetText)
                .font(.headline)
                .monospacedDigit()
        }
    }

    private var resetText: String {
        guard let window else { return "--" }
        guard let date = window.resetAt else { return "-" }
        if showDateTime {
            return DateFormatters.dateTime.string(from: date)
        }
        let time = DateFormatters.timeOnly.string(from: date)
        if showRelative {
            return "\(time) - \(relativeUntilText(date))"
        }
        return time
    }

    private func relativeUntilText(_ date: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(Date()))
        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 {
            return "time.minutesLater".widgetLocalized(minutes)
        }
        let hoursValue = seconds / 3600
        if hoursValue < 24 {
            let roundedHours = ceil(hoursValue * 10) / 10
            let hoursText = formatHours(roundedHours)
            return "time.hoursLater".widgetLocalized(hoursText)
        }
        let days = Int(hoursValue / 24)
        return "time.daysLater".widgetLocalized(days)
    }

    private func formatHours(_ hours: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.1f", hours)
    }
}

private enum DateFormatters {
    static var timeOnly: DateFormatter {
        makeFormatter(dateFormat: "HH:mm")
    }

    static var dateTime: DateFormatter {
        makeFormatter(dateFormat: "yyyy/MM/dd HH:mm")
    }

    private static func makeFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = WidgetLanguageHelper.localizedLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = dateFormat
        return formatter
    }
}

#Preview(as: .systemSmall) {
    CodexUsageLimitWidget()
} timeline: {
    UsageEntry(date: Date(), snapshot: nil, provider: .chatgptCodex)
}

private enum WidgetUsageColorResolver {
    static func statusColor(for window: UsageWindow?) -> Color {
        guard let window else { return .secondary }
        let level = UsageStatusLevelResolver.level(
            for: window.usedPercent,
            isRemainingMode: WidgetDisplayModeResolver.isRemainingMode
        )
        switch level {
        case .green:
            return .green
        case .orange:
            return .orange
        case .red:
            return .red
        }
    }
}

private enum WidgetDisplayModeResolver {
    static var isRemainingMode: Bool {
        // Compare cached display mode to determine remaining/used behavior.
        loadRawValue() == UsageDisplayModeRaw.remaining.rawValue
    }

    private static func loadRawValue() -> String {
        // Read cached mode from App Group defaults for widget rendering.
        let defaults = UserDefaults(suiteName: AppGroupConfig.groupId)
        return defaults?.string(forKey: SharedUserDefaultsKeys.cachedDisplayMode)
            ?? UsageDisplayModeRaw.used.rawValue
    }
}

// UsageDisplayModeRaw is shared in AgentLimitsShared.
