// MARK: - CustomUsageWidget.swift
// Configurable widget for script-backed custom usage services.

import AppIntents
import SwiftUI
import WidgetKit

/// Widget編集画面で選択可能なカスタム使用量サービスです。
struct CustomUsageServiceEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.custom.service")
    )
    static var defaultQuery = CustomUsageServiceEntityQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: displayName))
    }

    init(descriptor: CustomUsageServiceDescriptor) {
        id = descriptor.providerID
        displayName = descriptor.displayName
    }

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// App Groupのサービス台帳からWidget候補を返します。
struct CustomUsageServiceEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CustomUsageServiceEntity] {
        let descriptors = Dictionary(uniqueKeysWithValues: CustomUsageServiceDescriptorStore
            .loadDescriptors()
            .map { ($0.providerID, $0) })
        return identifiers.map { identifier in
            if let descriptor = descriptors[identifier] {
                return CustomUsageServiceEntity(descriptor: descriptor)
            }
            return CustomUsageServiceEntity(
                id: identifier,
                displayName: "widget.custom.unavailable".widgetLocalized()
            )
        }
    }

    func suggestedEntities() async throws -> [CustomUsageServiceEntity] {
        CustomUsageServiceDescriptorStore.loadDescriptors().map(CustomUsageServiceEntity.init)
    }

    func defaultResult() async -> CustomUsageServiceEntity? {
        CustomUsageServiceDescriptorStore.loadDescriptors().first.map(CustomUsageServiceEntity.init)
    }
}

/// カスタム使用量Widgetのサービス選択Intentです。
struct CustomUsageConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.custom.configuration"
    static var description = IntentDescription("widget.custom.configurationDescription")

    @Parameter(title: "widget.custom.service")
    var service: CustomUsageServiceEntity?

    init() {}

    init(service: CustomUsageServiceEntity) {
        self.service = service
    }
}

/// 選択サービスと最新スナップショットを保持するTimelineEntryです。
struct CustomUsageEntry: TimelineEntry {
    let date: Date
    let descriptor: CustomUsageServiceDescriptor?
    let snapshot: CustomUsageSnapshot?
    let selectedProviderID: String?
    let isServiceAvailable: Bool
}

/// カスタムサービスをApp Groupから読み込むTimelineProviderです。
struct CustomUsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CustomUsageEntry {
        let descriptor = CustomUsageServiceDescriptor(providerID: "example", displayName: "Custom Service")
        return CustomUsageEntry(
            date: Date(),
            descriptor: descriptor,
            snapshot: placeholderSnapshot,
            selectedProviderID: descriptor.providerID,
            isServiceAvailable: true
        )
    }

    func snapshot(
        for configuration: CustomUsageConfigurationIntent,
        in context: Context
    ) async -> CustomUsageEntry {
        makeEntry(for: configuration)
    }

    func timeline(
        for configuration: CustomUsageConfigurationIntent,
        in context: Context
    ) async -> Timeline<CustomUsageEntry> {
        let entry = makeEntry(for: configuration)
        let nextUpdate = Date().addingTimeInterval(UsageRefreshConfig.refreshIntervalSeconds)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func recommendations() -> [AppIntentRecommendation<CustomUsageConfigurationIntent>] {
        CustomUsageServiceDescriptorStore.loadDescriptors().map { descriptor in
            let entity = CustomUsageServiceEntity(descriptor: descriptor)
            return AppIntentRecommendation(
                intent: CustomUsageConfigurationIntent(service: entity),
                description: Text(descriptor.displayName)
            )
        }
    }

    private func makeEntry(for configuration: CustomUsageConfigurationIntent) -> CustomUsageEntry {
        let descriptors = CustomUsageServiceDescriptorStore.loadDescriptors()
        let selectedID = configuration.service?.id ?? descriptors.first?.providerID
        guard let selectedID else {
            return CustomUsageEntry(
                date: Date(),
                descriptor: nil,
                snapshot: nil,
                selectedProviderID: nil,
                isServiceAvailable: false
            )
        }
        let descriptor = descriptors.first { $0.providerID == selectedID }
        return CustomUsageEntry(
            date: Date(),
            descriptor: descriptor,
            snapshot: descriptor == nil ? nil : CustomUsageSnapshotStore.shared.loadSnapshot(providerID: selectedID),
            selectedProviderID: selectedID,
            isServiceAvailable: descriptor != nil
        )
    }

    private var placeholderSnapshot: CustomUsageSnapshot {
        CustomUsageSnapshot(
            schemaVersion: 1,
            provider: "example",
            fetchedAt: Date(),
            windows: [
                CustomUsageWindow(
                    kind: .fiveHours,
                    usedPercent: 42,
                    resetAt: Date().addingTimeInterval(2 * 60 * 60),
                    durationSeconds: UsageLimitDuration.fiveHours,
                    usedCount: nil,
                    limitCount: nil
                ),
                CustomUsageWindow(
                    kind: .oneWeek,
                    usedPercent: 68,
                    resetAt: Date().addingTimeInterval(4 * 24 * 60 * 60),
                    durationSeconds: UsageLimitDuration.sevenDays,
                    usedCount: nil,
                    limitCount: nil
                ),
            ]
        )
    }
}

/// カスタム使用量Widget本体です。
struct CustomUsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CustomUsageWidgetConfig.kind,
            intent: CustomUsageConfigurationIntent.self,
            provider: CustomUsageTimelineProvider()
        ) { entry in
            CustomUsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("widget.custom.title".widgetLocalized())
        .description("widget.custom.description".widgetLocalized())
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct CustomUsageWidgetEntryView: View {
    let entry: CustomUsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.descriptor?.displayName ?? "widget.custom.title".widgetLocalized())
                .font(.headline)
                .padding(.top, 8)
            content
        }
        .padding(.vertical, 4)
        .widgetURL(deepLinkURL)
    }

    @ViewBuilder
    private var content: some View {
        if !entry.isServiceAvailable, entry.selectedProviderID != nil {
            unavailableView("widget.custom.unavailable".widgetLocalized())
        } else if entry.selectedProviderID == nil {
            unavailableView("widget.custom.configure".widgetLocalized())
        } else if let snapshot = entry.snapshot, let descriptor = entry.descriptor {
            let windows = snapshot.windows.sorted { $0.kind.displayOrder < $1.kind.displayOrder }
            if family == .systemMedium {
                HStack(spacing: 14) {
                    donutRow(windows: windows, providerID: descriptor.providerID)
                    Spacer(minLength: 4)
                    detailColumn(windows: windows)
                        .frame(width: 145)
                }
                .frame(height: 100)
            } else {
                donutRow(windows: windows, providerID: descriptor.providerID)
                    .frame(height: 100)
            }
            Text("\("widget.updatedAt".widgetLocalized()) \(WidgetUpdateTimeFormatter.formatUpdateTime(since: snapshot.fetchedAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, -6)
        } else {
            unavailableView("widget.notFetched".widgetLocalized())
        }
    }

    private func donutRow(windows: [CustomUsageWindow], providerID: String) -> some View {
        HStack(spacing: windows.count == 1 ? 0 : 12) {
            ForEach(windows, id: \.kind) { window in
                CustomUsageDonutColumn(
                    serviceKey: .custom(providerID),
                    window: window.semanticWindow,
                    displayMode: displayMode
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func detailColumn(windows: [CustomUsageWindow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(windows, id: \.kind) { window in
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.kind.compactLabel)
                        .font(.caption.bold())
                    Text(window.resetAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let used = window.usedCount, let limit = window.limitCount {
                        Text("\(used) / \(limit)")
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
    }

    private func unavailableView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Text("widget.custom.openSettings".widgetLocalized())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var displayMode: UsageDisplayModeRaw {
        let rawValue = AppGroupDefaults.shared?.string(forKey: SharedUserDefaultsKeys.cachedDisplayMode)
        return UsageDisplayModeRaw(rawValue: rawValue ?? "")?.normalizedForWidget ?? .used
    }

    private var deepLinkURL: URL? {
        guard let providerID = entry.selectedProviderID else {
            return URL(string: "agentlimits://open-settings?tab=customUsage")
        }
        return URL(string: "agentlimits://open-custom-usage?provider=\(providerID)")
    }
}

private struct CustomUsageDonutColumn: View {
    let serviceKey: UsageServiceKey
    let window: SemanticUsageWindow
    let displayMode: UsageDisplayModeRaw

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: displayProgress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let pacemakerProgress {
                    Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 4).padding(7)
                    Circle()
                        .trim(from: 0, to: pacemakerProgress)
                        .stroke(
                            UsageColorSettings.loadPacemakerRingColor(),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(7)
                }
                Text(window.kind.compactLabel)
                    .font(.caption.bold())
            }
            .frame(width: 62, height: 62)
            percentText
                .font(.title3.bold().monospacedDigit())
        }
    }

    @ViewBuilder
    private var percentText: some View {
        let text = UsagePercentFormatter.formatPercentText(displayPercent)
        if isPacemakerIndicatorEnabled,
           let pacemaker = window.usageWindow.calculatePacemakerPercent() {
            let level = UsageStatusLevelResolver.levelForPacemakerMode(
                usedPercent: window.usedPercent,
                pacemakerPercent: pacemaker,
                warningDelta: PacemakerThresholdSettings.loadWarningDelta(),
                dangerDelta: PacemakerThresholdSettings.loadDangerDelta()
            )
            Text(text).foregroundStyle(statusColor)
            + Text(level.pacemakerArrowIcon).foregroundStyle(level.pacemakerIndicatorColor)
        } else {
            Text(text).foregroundStyle(statusColor)
        }
    }

    private var displayPercent: Double {
        displayMode.makeDisplayPercent(from: window.usedPercent, window: window.usageWindow)
    }

    private var displayProgress: Double { max(0, min(1, displayPercent / 100)) }

    private var pacemakerProgress: Double? {
        window.usageWindow.displayPacemakerPercent(for: displayMode).map { max(0, min(1, $0 / 100)) }
    }

    private var statusColor: Color {
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: serviceKey, windowKind: window.kind)
        switch UsageStatusLevelResolver.level(
            for: window.usedPercent,
            isRemainingMode: false,
            warningThreshold: thresholds.warningPercent,
            dangerThreshold: thresholds.dangerPercent
        ) {
        case .green: return UsageColorSettings.loadStatusGreenColor()
        case .orange: return UsageColorSettings.loadStatusOrangeColor()
        case .red: return UsageColorSettings.loadStatusRedColor()
        }
    }

    private var ringColor: Color {
        let defaults = AppGroupDefaults.shared
        return defaults?.bool(forKey: UsageColorKeys.donutUseStatus) == true
            ? statusColor
            : UsageColorSettings.loadDonutColor()
    }

    private var isPacemakerIndicatorEnabled: Bool {
        AppGroupDefaults.shared?.bool(forKey: SharedUserDefaultsKeys.menuBarShowPacemakerValue) ?? true
    }
}

private extension UsageDisplayModeRaw {
    var normalizedForWidget: UsageDisplayModeRaw {
        self == .usedWithPacemaker ? .used : self
    }
}
