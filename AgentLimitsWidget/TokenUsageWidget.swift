// MARK: - TokenUsageWidget.swift
// WidgetKit widgets for displaying ccusage token usage and costs.

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

/// Timeline provider that loads ccusage snapshots from App Group storage.
struct TokenUsageTimelineProvider: TimelineProvider {
    let provider: TokenUsageProvider

    func placeholder(in context: Context) -> TokenUsageEntry {
        // Use placeholder snapshot for gallery preview.
        TokenUsageEntry(date: Date(), snapshot: placeholderSnapshot, provider: provider)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenUsageEntry) -> Void) {
        if context.isPreview {
            // Preview mode uses placeholder data for fast rendering.
            completion(TokenUsageEntry(date: Date(), snapshot: placeholderSnapshot, provider: provider))
            return
        }
        // Load latest snapshot from App Group storage.
        let snapshot = TokenUsageSnapshotStore.shared.loadSnapshot(for: provider)
        completion(TokenUsageEntry(date: Date(), snapshot: snapshot, provider: provider))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenUsageEntry>) -> Void) {
        // Read snapshot and schedule the next refresh based on shared interval.
        let snapshot = TokenUsageSnapshotStore.shared.loadSnapshot(for: provider)
        let entry = TokenUsageEntry(date: Date(), snapshot: snapshot, provider: provider)
        let nextUpdate = Date().addingTimeInterval(TokenUsageRefreshConfig.refreshIntervalSeconds)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private var placeholderSnapshot: TokenUsageSnapshot {
        TokenUsageSnapshot(
            provider: provider,
            fetchedAt: Date(),
            today: TokenUsagePeriod(costUSD: 0.28, totalTokens: 6378000),
            thisWeek: TokenUsagePeriod(costUSD: 8.59, totalTokens: 22648000),
            thisMonth: TokenUsagePeriod(costUSD: 79.39, totalTokens: 87200000),
            dailyUsage: generatePlaceholderDailyUsage()
        )
    }

    /// Generates placeholder daily usage data for preview.
    private func generatePlaceholderDailyUsage() -> [DailyUsageEntry] {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }

        return range.map { day in
            let dateString = String(
                format: "%04d-%02d-%02d",
                components.year ?? 2025,
                components.month ?? 1,
                day
            )
            // Random usage for preview visualization
            let tokens = [0, 100000, 500000, 1000000, 2000000].randomElement() ?? 0
            return DailyUsageEntry(date: dateString, totalTokens: tokens)
        }
    }
}

// MARK: - Timeline Entry

/// Timeline entry containing the latest token usage snapshot.
struct TokenUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: TokenUsageSnapshot?
    let provider: TokenUsageProvider
}

// MARK: - Widget Entry View

/// Widget entry view for ccusage token usage.
struct TokenUsageWidgetEntryView: View {
    var entry: TokenUsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidgetContent
        case .systemMedium:
            mediumWidgetContent
        default:
            smallWidgetContent
        }
    }

    // MARK: - Small Widget Content

    @ViewBuilder
    private var smallWidgetContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            Text(entry.provider.widgetDisplayName)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .padding(.top, 8)

            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    VStack(alignment: .leading, spacing: 4) {
                        usageRow(
                            label: "widget.tokenUsage.today".widgetLocalized(),
                            period: snapshot.today
                        )
                        usageRow(
                            label: "widget.tokenUsage.thisWeek".widgetLocalized(),
                            period: snapshot.thisWeek
                        )
                        usageRow(
                            label: "widget.tokenUsage.thisMonth".widgetLocalized(),
                            period: snapshot.thisMonth
                        )
                    }

                    // Last updated
                    HStack(spacing: 2) {
                        Text("widget.updated".widgetLocalized())
                        Text(WidgetRelativeTimeFormatter.makeRelativeUpdatedText(since: snapshot.fetchedAt))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            } else {
                notFetchedView
            }
        }
        .padding(.vertical, 4)
        .widgetURL(entry.provider.widgetDeepLinkURL)
    }

    // MARK: - Medium Widget Content

    @ViewBuilder
    private var mediumWidgetContent: some View {
        HStack(spacing: 8) {
            // Left side: Usage summary (fixed width, same as small widget)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.provider.widgetDisplayName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let snapshot = entry.snapshot {
                    VStack(alignment: .leading, spacing: 4) {
                        usageRow(
                            label: "widget.tokenUsage.today".widgetLocalized(),
                            period: snapshot.today
                        )
                        usageRow(
                            label: "widget.tokenUsage.thisWeek".widgetLocalized(),
                            period: snapshot.thisWeek
                        )
                        usageRow(
                            label: "widget.tokenUsage.thisMonth".widgetLocalized(),
                            period: snapshot.thisMonth
                        )
                    }

                    HStack(spacing: 2) {
                        Text("widget.updated".widgetLocalized())
                        Text(WidgetRelativeTimeFormatter.makeRelativeUpdatedText(since: snapshot.fetchedAt))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    notFetchedView
                }
            }
            .frame(width: 155, alignment: .leading)

            // Right side: Heatmap (expanded to fill remaining space)
            if let snapshot = entry.snapshot {
                HeatmapView(
                    dailyUsage: snapshot.dailyUsage,
                    currentDate: entry.date,
                    cellSize: 13
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // Placeholder heatmap
                HeatmapView(
                    dailyUsage: [],
                    currentDate: entry.date,
                    cellSize: 13
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .widgetURL(entry.provider.widgetDeepLinkURL)
    }

    // MARK: - Not Fetched View

    @ViewBuilder
    private var notFetchedView: some View {
        Spacer()
        Text("widget.notFetched".widgetLocalized())
            .font(.body)
            .foregroundStyle(.secondary)
        Text("widget.pleaseOpenApp".widgetLocalized())
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
    }

    // MARK: - Usage Row

    @ViewBuilder
    private func usageRow(label: String, period: TokenUsagePeriod) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label)
                    .font(.body)
                    .padding(.leading, 8)
                Spacer()
                Text(TokenUsageFormatter.formatCost(period.costUSD))
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            HStack {
                Spacer()
                Text(TokenUsageFormatter.formatTokens(period.totalTokens))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Widget Definitions

struct ClaudeTokenUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: TokenUsageProvider.claude.widgetKind,
            provider: TokenUsageTimelineProvider(provider: .claude)
        ) { entry in
            TokenUsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(TokenUsageProvider.claude.widgetDisplayName)
        .description("widget.tokenUsageDescription".widgetLocalized())
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CodexTokenUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: TokenUsageProvider.codex.widgetKind,
            provider: TokenUsageTimelineProvider(provider: .codex)
        ) { entry in
            TokenUsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(TokenUsageProvider.codex.widgetDisplayName)
        .description("widget.tokenUsageDescription".widgetLocalized())
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    ClaudeTokenUsageWidget()
} timeline: {
    TokenUsageEntry(
        date: Date(),
        snapshot: TokenUsageSnapshot(
            provider: .claude,
            fetchedAt: Date(),
            today: TokenUsagePeriod(costUSD: 0.28, totalTokens: 6378000),
            thisWeek: TokenUsagePeriod(costUSD: 8.59, totalTokens: 22648000),
            thisMonth: TokenUsagePeriod(costUSD: 79.39, totalTokens: 87200000),
            dailyUsage: []
        ),
        provider: .claude
    )
}

#Preview("Medium", as: .systemMedium) {
    ClaudeTokenUsageWidget()
} timeline: {
    TokenUsageEntry(
        date: Date(),
        snapshot: TokenUsageSnapshot(
            provider: .claude,
            fetchedAt: Date(),
            today: TokenUsagePeriod(costUSD: 0.28, totalTokens: 6378000),
            thisWeek: TokenUsagePeriod(costUSD: 8.59, totalTokens: 22648000),
            thisMonth: TokenUsagePeriod(costUSD: 79.39, totalTokens: 87200000),
            dailyUsage: (1...31).map { day in
                DailyUsageEntry(
                    date: String(format: "2025-12-%02d", day),
                    totalTokens: [0, 100000, 500000, 1000000, 2000000].randomElement() ?? 0
                )
            }
        ),
        provider: .claude
    )
}
