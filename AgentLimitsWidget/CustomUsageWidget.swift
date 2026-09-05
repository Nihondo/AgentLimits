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
            let windows = snapshot.windows
                .map(\.semanticWindow)
                .sorted { $0.kind.displayOrder < $1.kind.displayOrder }
            if family == .systemMedium {
                GeometryReader { proxy in
                    let detailWidth = WidgetDonutLayout.detailColumnWidth
                    let spacing = WidgetDonutLayout.columnSpacing
                    let leftWidth = max(0, proxy.size.width - detailWidth - spacing)
                    let donutSize = WidgetDonutLayout.donutSize(availableWidth: leftWidth, columnCount: windows.count)
                    let columnHeight = WidgetDonutLayout.columnHeight(donutSize: donutSize)
                    HStack(alignment: .center, spacing: 0) {
                        donutRow(windows: windows, providerID: descriptor.providerID, donutSize: donutSize)
                            .frame(width: leftWidth, alignment: .leading)
                        Spacer(minLength: 0)
                        detailColumn(windows: windows)
                            .frame(width: detailWidth, alignment: .trailing)
                            .padding(.trailing, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: max(columnHeight, 96), alignment: .center)
                }
                .frame(height: WidgetDonutLayout.contentHeight)
                .padding(.top, WidgetDonutLayout.contentTopPadding)
            } else {
                GeometryReader { proxy in
                    let donutSize = WidgetDonutLayout.donutSize(availableWidth: proxy.size.width, columnCount: windows.count)
                    donutRow(windows: windows, providerID: descriptor.providerID, donutSize: donutSize)
                        .frame(
                            height: WidgetDonutLayout.columnHeight(donutSize: donutSize),
                            alignment: .center
                        )
                }
                .frame(height: WidgetDonutLayout.contentHeight)
                .padding(.top, WidgetDonutLayout.contentTopPadding)
            }
            Text("\("widget.updatedAt".widgetLocalized()) \(WidgetUpdateTimeFormatter.formatUpdateTime(since: snapshot.fetchedAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, -6)
        } else {
            unavailableView("widget.notFetched".widgetLocalized())
        }
    }

    private func donutRow(windows: [SemanticUsageWindow], providerID: String, donutSize: CGFloat) -> some View {
        HStack(spacing: windows.count == 1 ? 0 : WidgetDonutLayout.columnSpacing) {
            ForEach(windows, id: \.kind) { window in
                CustomUsageDonutColumn(
                    serviceKey: .custom(providerID),
                    window: window,
                    displayMode: displayMode,
                    size: donutSize
                )
                .frame(maxWidth: .infinity)
                .frame(
                    height: WidgetDonutLayout.columnHeight(donutSize: donutSize),
                    alignment: .center
                )
            }
        }
    }

    private func detailColumn(windows: [SemanticUsageWindow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(windows.enumerated()), id: \.element.kind) { index, window in
                VStack(alignment: .leading, spacing: 2) {
                    UsageDetailSectionView(
                        title: window.hasCustomLabel ? window.displayLabel : window.kind.detailTitle,
                        window: window.usageWindow,
                        showRelative: windows.count > 1 && index == 0,
                        showDateTime: !(windows.count > 1 && index == 0),
                        showReset: window.resetAt != nil
                    )
                    if let used = window.usedCount, let limit = window.limitCount {
                        Text("  \(used) / \(limit)")
                            .font(.headline)
                            .monospacedDigit()
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
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            UsageRingGaugeView(
                centerLabel: window.displayLabel,
                progress: displayProgress,
                ringColor: ringColor,
                pacemakerSegments: pacemakerSegments,
                pacemakerProgress: pacemakerProgress,
                pacemakerRingColor: UsageColorSettings.loadPacemakerRingColor(),
                pacemakerWarningColor: UsageColorSettings.loadPacemakerStatusOrangeColor(),
                pacemakerDangerColor: UsageColorSettings.loadPacemakerStatusRedColor(),
                divisionCount: window.hasCustomLabel ? 1 : window.usageWindow.pacemakerDivisionCount,
                size: size,
                accessibilityPercentText: UsagePercentFormatter.formatPercentText(displayPercent, placeholder: "0%")
            )
            percentText
                .font(.title3.bold().monospacedDigit())
        }
    }

    private var isPacemakerRingWarningEnabled: Bool {
        PacemakerRingWarningSettings.isWarningEnabled()
    }

    private var pacemakerSegments: PacemakerRingSegments? {
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: serviceKey, windowKind: window.kind)
        let isEligible = window.canShowPacemaker
            && isPacemakerRingWarningEnabled
            && displayMode != .remaining
            && !WidgetRingWarningGate.isBlockedByStatusColor(usedPercent: window.usedPercent, thresholds: thresholds)
        return PacemakerRingSegments.compute(
            usedPercent: window.usedPercent,
            pacemakerPercent: pacemakerPercent,
            progress: displayProgress,
            isEligible: isEligible
        )
    }

    @ViewBuilder
    private var percentText: some View {
        let text = UsagePercentFormatter.formatPercentText(displayPercent)
        if isPacemakerIndicatorEnabled,
           let pacemaker = pacemakerPercent {
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
        guard window.canShowPacemaker else { return nil }
        return window.usageWindow.displayPacemakerPercent(for: displayMode).map { max(0, min(1, $0 / 100)) }
    }

    private var pacemakerPercent: Double? {
        guard window.canShowPacemaker else { return nil }
        return window.usageWindow.calculatePacemakerPercent()
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

private extension SemanticUsageWindowKind {
    /// 組み込みWidgetの詳細列と同じ見出し文言を、意味ベースの利用枠種別から解決する。
    var detailTitle: String {
        switch self {
        case .fiveHours: return "widget.5hourLimit".widgetLocalized()
        case .oneWeek: return "widget.weeklyLimit".widgetLocalized()
        case .oneMonth: return "widget.monthlyLimit".widgetLocalized()
        }
    }
}
