// MARK: - TokenUsageWidget.swift
// WidgetKit widgets for displaying ccusage token usage and costs.

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct TokenUsageTimelineProvider: TimelineProvider {
    let provider: TokenUsageProvider

    func placeholder(in context: Context) -> TokenUsageEntry {
        TokenUsageEntry(date: Date(), snapshot: placeholderSnapshot, provider: provider)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenUsageEntry) -> Void) {
        if context.isPreview {
            completion(TokenUsageEntry(date: Date(), snapshot: placeholderSnapshot, provider: provider))
            return
        }
        let snapshot = TokenUsageSnapshotStore.shared.loadSnapshot(for: provider)
        completion(TokenUsageEntry(date: Date(), snapshot: snapshot, provider: provider))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenUsageEntry>) -> Void) {
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
            thisMonth: TokenUsagePeriod(costUSD: 79.39, totalTokens: 87200000)
        )
    }
}

// MARK: - Timeline Entry

struct TokenUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: TokenUsageSnapshot?
    let provider: TokenUsageProvider
}

// MARK: - Widget Entry View

struct TokenUsageWidgetEntryView: View {
    var entry: TokenUsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
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
                        // Today
                        usageRow(
                            label: "widget.tokenUsage.today".widgetLocalized(),
                            period: snapshot.today
                        )

                        // This Week
                        usageRow(
                            label: "widget.tokenUsage.thisWeek".widgetLocalized(),
                            period: snapshot.thisWeek
                        )

                        // This Month
                        usageRow(
                            label: "widget.tokenUsage.thisMonth".widgetLocalized(),
                            period: snapshot.thisMonth
                        )
                    }

                    // Last updated
                    HStack(spacing: 2) {
                        Text("widget.updated".widgetLocalized())
                        Text(relativeUpdatedText(snapshot.fetchedAt))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            } else {
                Spacer()
                Text("widget.notFetched".widgetLocalized())
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("widget.pleaseOpenApp".widgetLocalized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .widgetURL(entry.provider.widgetDeepLinkURL)
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
                Text(formatCost(period.costUSD))
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            HStack {
                Spacer()
                Text(formatTokens(period.totalTokens))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Formatting

    private func formatCost(_ cost: Double) -> String {
        String(format: "$ %.2f", cost)
    }

    private func formatTokens(_ tokens: Int) -> String {
        let kTokens = Double(tokens) / 1000.0
        if kTokens >= 1000 {
            return String(format: "%.1fM Tokens", kTokens / 1000.0)
        } else if kTokens >= 1 {
            return String(format: "%.0fK Tokens", kTokens)
        } else {
            return "\(tokens) Tokens"
        }
    }

    private func relativeUpdatedText(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 {
            return "time.withinMinute".widgetLocalized()
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return String(format: "time.minutesAgo".widgetLocalized(), minutes)
        }
        let hours = minutes / 60
        return String(format: "time.hoursAgo".widgetLocalized(), hours)
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
        .supportedFamilies([.systemSmall])
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
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ClaudeTokenUsageWidget()
} timeline: {
    TokenUsageEntry(
        date: Date(),
        snapshot: TokenUsageSnapshot(
            provider: .claude,
            fetchedAt: Date(),
            today: TokenUsagePeriod(costUSD: 0.28, totalTokens: 6378000),
            thisWeek: TokenUsagePeriod(costUSD: 8.59, totalTokens: 22648000),
            thisMonth: TokenUsagePeriod(costUSD: 79.39, totalTokens: 87200000)
        ),
        provider: .claude
    )
}
