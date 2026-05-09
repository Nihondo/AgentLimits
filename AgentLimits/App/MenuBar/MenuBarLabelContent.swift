// MARK: - MenuBarLabelContent.swift
// メニューバーアイコンの SwiftUI コンテンツ。
// ImageRenderer でレンダリングして NSStatusItem.button.image に設定する。

import SwiftUI

/// メニューバーアイコン全体のレイアウト（プロバイダーステータスを横並びで表示）
struct MenuBarLabelContentView: View {
    let codexSnapshot: UsageSnapshot?
    let claudeSnapshot: UsageSnapshot?
    let copilotSnapshot: UsageSnapshot?
    let displayMode: UsageDisplayMode

    var body: some View {
        HStack(spacing: 6) {
            Image(.menuBarIcon)
            if let codexSnapshot {
                MenuBarProviderStatusView(
                    provider: .chatgptCodex,
                    primaryWindow: codexSnapshot.primaryWindow,
                    secondaryWindow: codexSnapshot.secondaryWindow,
                    displayMode: displayMode
                )
            }
            if let claudeSnapshot {
                MenuBarProviderStatusView(
                    provider: .claudeCode,
                    primaryWindow: claudeSnapshot.primaryWindow,
                    secondaryWindow: claudeSnapshot.secondaryWindow,
                    displayMode: displayMode
                )
            }
            if let copilotSnapshot {
                MenuBarProviderStatusView(
                    provider: .githubCopilot,
                    primaryWindow: copilotSnapshot.primaryWindow,
                    secondaryWindow: copilotSnapshot.secondaryWindow,
                    displayMode: displayMode
                )
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

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(provider.displayName)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.primary)
            MenuBarPercentLineView(
                provider: provider,
                primaryWindow: primaryWindow,
                secondaryWindow: secondaryWindow,
                displayMode: displayMode
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
                if arrowIcon.isEmpty {
                    Text(displayText).foregroundColor(statusColor)
                } else {
                    Text(displayText).foregroundColor(statusColor)
                    + Text(arrowIcon).foregroundColor(indicatorColor)
                }
            } else {
                Text(displayText).foregroundColor(statusColor)
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
