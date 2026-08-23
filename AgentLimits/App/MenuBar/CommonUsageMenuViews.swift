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
                ForEach(Array(snapshot.windows.enumerated()), id: \.element.kind) { index, window in
                    if index > 0 { Text("/").foregroundStyle(.secondary) }
                    CommonUsagePercentText(
                        serviceKey: snapshot.serviceKey,
                        window: window,
                        displayMode: displayMode,
                        colorScheme: colorScheme
                    )
                }
            }
            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
            .monospacedDigit()
        }
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
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let lastError: String?
    @State private var isHovered = false

    var body: some View {
        Button(action: openDestination) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(snapshot.displayName).fontWeight(.semibold)
                    Spacer()
                    if lastError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(snapshot.fetchedAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                ForEach(snapshot.windows, id: \.kind) { window in
                    windowRow(window)
                }
                HStack(spacing: 8) {
                    statusDate("customUsage.lastAttempt".localized(), date: lastAttemptAt)
                    statusDate(
                        "customUsage.lastSuccess".localized(),
                        date: lastSuccessAt ?? snapshot.fetchedAt
                    )
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
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.accentColor.opacity(0.8) : .clear)
                .padding(.horizontal, 5)
        )
        .onHover { isHovered = $0 }
    }

    private func statusDate(_ label: String, date: Date?) -> some View {
        Group {
            if let date {
                Text("\(label): ") + Text(date, style: .relative)
            } else {
                Text("\(label): -")
            }
        }
        .font(.system(size: 8.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func windowRow(_ window: SemanticUsageWindow) -> some View {
        let usageWindow = window.usageWindow
        let percent = displayMode.displayPercent(from: window.usedPercent, window: usageWindow)
        return HStack(spacing: 6) {
            Text(window.kind.compactLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            VStack(spacing: 2) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(statusColor(for: window))
                                .frame(width: proxy.size.width * max(0, min(1, percent / 100)))
                        }
                }
                .frame(height: 7)
                if let pacemaker = usageWindow.displayPacemakerPercent(for: displayMode.makeDisplayModeRaw()) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(UsageColorSettings.loadPacemakerRingColor())
                                    .frame(width: proxy.size.width * max(0, min(1, pacemaker / 100)))
                            }
                    }
                    .frame(height: 3)
                }
            }
            Text(UsagePercentFormatter.formatPercentText(percent))
                .font(.system(size: 11))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func statusColor(for window: SemanticUsageWindow) -> Color {
        let thresholds = UsageStatusThresholdStore.loadThresholds(
            for: snapshot.serviceKey,
            windowKind: window.kind
        )
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
