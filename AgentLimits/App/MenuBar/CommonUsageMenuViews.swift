// MARK: - CommonUsageMenuViews.swift
// Menu bar views shared by dynamic custom usage services.

import AppKit
import SwiftUI

/// 動的サービスを含むメニューバーラベルを描画します。
struct CommonUsageMenuBarLabelView: View {
    let orderedSnapshots: [(serviceKey: UsageServiceKey, snapshot: UsagePresentationSnapshot?)]
    let displayMode: UsageDisplayMode
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 6) {
            if orderedSnapshots.allSatisfy({ $0.snapshot == nil }) {
                Image(.menuBarIcon)
            }
            ForEach(orderedSnapshots, id: \.serviceKey) { item in
                if let snapshot = item.snapshot {
                    CommonUsageMenuBarServiceView(
                        snapshot: snapshot,
                        displayMode: displayMode,
                        colorScheme: colorScheme
                    )
                }
            }
        }
    }
}

private struct CommonUsageMenuBarServiceView: View {
    let snapshot: UsagePresentationSnapshot
    let displayMode: UsageDisplayMode
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(snapshot.displayName)
                .font(.system(size: 9.5, weight: .semibold))
            HStack(spacing: 2) {
                ForEach(Array(displayWindowSlots.enumerated()), id: \.offset) { index, window in
                    if index > 0 { Text("/").foregroundStyle(.secondary) }
                    if let window {
                        CommonUsagePercentText(
                            serviceKey: snapshot.serviceKey,
                            window: window,
                            displayMode: displayMode,
                            colorScheme: colorScheme
                        )
                    } else {
                        Text(UsagePercentFormatter.formatPercentText(nil)).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
            .monospacedDigit()
        }
    }

    // 一部のウィンドウだけ未取得の場合（例: Codexが週次のみ先に取得できた等）も、
    // 想定される枠に対して「--」プレースホルダーを補って枠の存在がわかるようにする。
    // 実データの種別が想定外（例: 月次のみ判定に切り替わった等）の場合はそのまま実データを使う。
    private var displayWindowSlots: [SemanticUsageWindow?] {
        let expectedKinds = snapshot.serviceKey.expectedWindowKinds
        guard !expectedKinds.isEmpty,
              snapshot.windows.allSatisfy({ expectedKinds.contains($0.kind) }) else {
            return snapshot.windows
        }
        let byKind = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.kind, $0) })
        return expectedKinds.map { byKind[$0] }
    }
}

private extension UsageServiceKey {
    /// このサービスで通常期待されるウィンドウ種別（組み込みサービスのみ既知の構成を返す）。
    var expectedWindowKinds: [SemanticUsageWindowKind] {
        guard let provider = builtInProvider else { return [] }
        return provider == .githubCopilot ? [.oneMonth] : [.fiveHours, .oneWeek]
    }
}

private struct CommonUsagePercentText: View {
    let serviceKey: UsageServiceKey
    let window: SemanticUsageWindow
    let displayMode: UsageDisplayMode
    let colorScheme: ColorScheme
    @AppStorage(UserDefaultsKeys.menuBarShowPacemakerValue, store: AppGroupDefaults.shared)
    private var showPacemakerValue = true

    var body: some View {
        let usageWindow = window.usageWindow
        let percent = displayMode.displayPercent(from: window.usedPercent, window: usageWindow)
        let text = UsagePercentFormatter.formatPercentText(percent)
        let color = adjustedColor(statusColor)
        if showPacemakerValue,
           let pacemaker = usageWindow.calculatePacemakerPercent() {
            let level = UsageStatusLevelResolver.levelForPacemakerMode(
                usedPercent: window.usedPercent,
                pacemakerPercent: pacemaker,
                warningDelta: PacemakerThresholdSettings.loadWarningDelta(),
                dangerDelta: PacemakerThresholdSettings.loadDangerDelta()
            )
            if level.pacemakerArrowIcon.isEmpty {
                Text(text).foregroundStyle(color)
            } else {
                Text(text).foregroundStyle(color)
                + Text(level.pacemakerArrowIcon).foregroundStyle(adjustedColor(level.pacemakerIndicatorColor))
            }
        } else {
            Text(text).foregroundStyle(color)
        }
    }

    private var statusColor: Color {
        let thresholds = UsageStatusThresholdStore.loadThresholds(
            for: serviceKey,
            windowKind: window.kind
        )
        let level = UsageStatusLevelResolver.level(
            for: window.usedPercent,
            isRemainingMode: false,
            warningThreshold: thresholds.warningPercent,
            dangerThreshold: thresholds.dangerPercent
        )
        switch level {
        case .green: return UsageColorSettings.loadStatusGreenColor()
        case .orange: return UsageColorSettings.loadStatusOrangeColor()
        case .red: return UsageColorSettings.loadStatusRedColor()
        }
    }

    private func adjustedColor(_ color: Color) -> Color {
        guard let value = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let target = colorScheme == .light ? 0.0 : 1.0
        let amount = 0.3
        return Color(
            .sRGB,
            red: Double(value.redComponent) + ((target - Double(value.redComponent)) * amount),
            green: Double(value.greenComponent) + ((target - Double(value.greenComponent)) * amount),
            blue: Double(value.blueComponent) + ((target - Double(value.blueComponent)) * amount),
            opacity: Double(value.alphaComponent)
        )
    }
}

/// カスタムサービスのメニューダッシュボード行です。
struct CustomUsageDashboardMenuItemView: View {
    let snapshot: UsagePresentationSnapshot
    let displayMode: UsageDisplayMode
    let websiteURL: URL?
    let lastError: String?
    @State private var isHovered = false

    var body: some View {
        Button(action: openDestination) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(snapshot.displayName).fontWeight(.semibold)
                    Spacer()
                    if lastError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    DashboardResetLabels(resetDates: snapshot.windows.map { Optional($0.resetAt) })
                }
                .font(.system(size: 11))
                ForEach(snapshot.windows, id: \.kind) { window in
                    windowRow(window)
                }
                if let lastError {
                    Text(lastError)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 18)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dashboardRowStyle(isHovered: isHovered)
        .onHover { isHovered = $0 }
    }

    private func windowRow(_ window: SemanticUsageWindow) -> some View {
        let usageWindow = window.usageWindow
        let displayModeRaw = displayMode.makeDisplayModeRaw()
        let percent = displayMode.displayPercent(from: window.usedPercent, window: usageWindow)
        let pacemakerPercent = usageWindow.displayPacemakerPercent(for: displayModeRaw)
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: snapshot.serviceKey, windowKind: window.kind)
        let isEligible = PacemakerRingWarningSettings.isWarningEnabled()
            && displayModeRaw != .remaining
            && !LinearWarningGate.isBlockedByStatusColor(usedPercent: window.usedPercent, thresholds: thresholds)
        let segments = PacemakerLinearSegments.compute(
            usedPercent: window.usedPercent,
            pacemakerPercent: usageWindow.calculatePacemakerPercent(),
            progress: max(0, min(1, percent / 100)),
            isEligible: isEligible
        )

        return HStack(spacing: 6) {
            Text(window.kind.compactLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(minWidth: 18, alignment: .trailing)

            UsageLinearGaugeView(
                usageProgress: max(0, min(1, percent / 100)),
                barColor: statusColor(for: window, thresholds: thresholds),
                pacemakerSegments: segments,
                pacemakerProgress: pacemakerPercent.map { max(0, min(1, $0 / 100)) },
                pacemakerRingColor: UsageColorSettings.loadPacemakerRingColor(),
                pacemakerWarningColor: UsageColorSettings.loadPacemakerStatusOrangeColor(),
                pacemakerDangerColor: UsageColorSettings.loadPacemakerStatusRedColor(),
                divisionCount: usageWindow.pacemakerDivisionCount
            )

            Text(UsagePercentFormatter.formatPercentText(percent))
                .font(.system(size: 11))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func statusColor(for window: SemanticUsageWindow, thresholds: UsageStatusThresholds) -> Color {
        let defaults = AppGroupDefaults.shared
        guard defaults?.bool(forKey: UsageColorKeys.donutUseStatus) == true else {
            return UsageColorSettings.loadDonutColor()
        }
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

    private func openDestination() {
        if let websiteURL {
            NSWorkspace.shared.open(websiteURL)
        } else if let url = URL(string: "agentlimits://open-settings?tab=customUsage&provider=\(snapshot.serviceKey.customProviderID ?? "")") {
            NSWorkspace.shared.open(url)
        }
    }
}
