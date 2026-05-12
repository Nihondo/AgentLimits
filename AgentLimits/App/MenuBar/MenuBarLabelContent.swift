// MARK: - MenuBarLabelContent.swift
// メニューバーアイコンの SwiftUI コンテンツ。
// ImageRenderer でレンダリングして NSStatusItem.button.image に設定する。

import SwiftUI
import AppKit

/// メニューバーアイコン全体のレイアウト（プロバイダーステータスを横並びで表示）
struct MenuBarLabelContentView: View {
    /// 表示順序付きの (プロバイダ, スナップショット?) 配列。nil は非表示。
    let orderedSnapshots: [(provider: UsageProvider, snapshot: UsageSnapshot?)]
    let displayMode: UsageDisplayMode
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 6) {
            if orderedSnapshots.allSatisfy({ $0.snapshot == nil }) {
                Image(.menuBarIcon)
            }
            ForEach(orderedSnapshots, id: \.provider.id) { item in
                if let snapshot = item.snapshot {
                    MenuBarProviderStatusView(
                        provider: item.provider,
                        primaryWindow: snapshot.primaryWindow,
                        secondaryWindow: snapshot.secondaryWindow,
                        displayMode: displayMode,
                        colorScheme: colorScheme
                    )
                }
            }
        }
    }
}

/// 1プロバイダーのメニューバーステータス（名前＋パーセント行）
struct MenuBarProviderStatusView: View {
    let provider: UsageProvider
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
    let displayMode: UsageDisplayMode
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(provider.displayName)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.primary)
            MenuBarPercentLineView(
                provider: provider,
                primaryWindow: primaryWindow,
                secondaryWindow: secondaryWindow,
                displayMode: displayMode,
                colorScheme: colorScheme
            )
        }
    }
}

/// 5h/週次のパーセント表示行（ペースメーカー矢印付き）
struct MenuBarPercentLineView: View {
    let provider: UsageProvider
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
    let displayMode: UsageDisplayMode
    let colorScheme: ColorScheme
    @AppStorage(UserDefaultsKeys.menuBarShowPacemakerValue, store: AppGroupDefaults.shared)
    private var showPacemakerValue: Bool = true
    @AppStorage(UsageColorKeys.statusGreen, store: AppGroupDefaults.shared)
    private var statusGreenHex: String = ""
    @AppStorage(UsageColorKeys.statusOrange, store: AppGroupDefaults.shared)
    private var statusOrangeHex: String = ""
    @AppStorage(UsageColorKeys.statusRed, store: AppGroupDefaults.shared)
    private var statusRedHex: String = ""

    var body: some View {
        HStack(spacing: 2) {
            percentTextView(primaryWindow, windowKind: .primary)
            if provider != .githubCopilot {
                Text("/")
                    .foregroundStyle(.secondary)
                percentTextView(secondaryWindow, windowKind: .secondary)
            }
        }
        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func percentTextView(_ window: UsageWindow?, windowKind: UsageWindowKind) -> some View {
        if let window {
            let statusColor = resolveStatusColor(window, windowKind: windowKind)
            let adjustedStatusColor = MenuBarTextColorAdjuster.adjustedColor(
                statusColor,
                for: colorScheme
            )
            let percent = displayMode.displayPercent(from: window.usedPercent, window: window)
            let displayText = UsagePercentFormatter.formatPercentText(percent)
            if showPacemakerValue,
               let pacemakerPercent = window.calculatePacemakerPercent() {
                let level = UsageStatusLevelResolver.levelForPacemakerMode(
                    usedPercent: window.usedPercent,
                    pacemakerPercent: pacemakerPercent,
                    warningDelta: PacemakerThresholdSettings.loadWarningDelta(),
                    dangerDelta: PacemakerThresholdSettings.loadDangerDelta()
                )
                let arrowIcon = level.pacemakerArrowIcon
                let indicatorColor = level.pacemakerIndicatorColor
                let adjustedIndicatorColor = MenuBarTextColorAdjuster.adjustedColor(
                    indicatorColor,
                    for: colorScheme
                )
                if arrowIcon.isEmpty {
                    Text(displayText).foregroundColor(adjustedStatusColor)
                } else {
                    Text(displayText).foregroundColor(adjustedStatusColor)
                    + Text(arrowIcon).foregroundColor(adjustedIndicatorColor)
                }
            } else {
                Text(displayText).foregroundColor(adjustedStatusColor)
            }
        } else {
            Text(UsagePercentFormatter.formatPercentText(nil)).foregroundStyle(.secondary)
        }
    }

    private func resolveStatusColor(_ window: UsageWindow?, windowKind: UsageWindowKind) -> Color {
        guard let window else { return .secondary }
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: provider, windowKind: windowKind)
        let level = UsageStatusLevelResolver.level(
            for: window.usedPercent,
            isRemainingMode: false,
            warningThreshold: thresholds.warningPercent,
            dangerThreshold: thresholds.dangerPercent
        )
        switch level {
        case .green: return resolveStoredColor(from: statusGreenHex, defaultColor: .green)
        case .orange: return resolveStoredColor(from: statusOrangeHex, defaultColor: .orange)
        case .red: return resolveStoredColor(from: statusRedHex, defaultColor: .red)
        }
    }

    private func resolveStoredColor(from storedValue: String, defaultColor: Color) -> Color {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return ColorHexCodec.resolveColor(from: trimmed.isEmpty ? nil : trimmed, defaultColor: defaultColor)
    }
}

private enum MenuBarTextColorAdjuster {
    private static let darkenAmount = 0.3
    private static let lightenAmount = 0.3

    static func adjustedColor(_ color: Color, for colorScheme: ColorScheme) -> Color {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            return color
        }
        let target = colorScheme == .light ? 0.0 : 1.0
        let amount = colorScheme == .light ? darkenAmount : lightenAmount

        return Color(
            .sRGB,
            red: blend(nsColor.redComponent, toward: target, amount: amount),
            green: blend(nsColor.greenComponent, toward: target, amount: amount),
            blue: blend(nsColor.blueComponent, toward: target, amount: amount),
            opacity: Double(nsColor.alphaComponent)
        )
    }

    private static func blend(_ component: CGFloat, toward target: Double, amount: Double) -> Double {
        let value = Double(component)
        return value + ((target - value) * amount)
    }
}
