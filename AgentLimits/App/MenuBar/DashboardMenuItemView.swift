// MARK: - DashboardMenuItemView.swift
// NSMenuItem.view に設定する 1プロバイダーぶんのダッシュボード行。
// 上部: プロバイダー名 + 残り時間 + リセット時刻
// 中部: ウィンドウごとの線形バー（ラベル / バー / パーセント）

import SwiftUI

/// メニューバーダッシュボードの1プロバイダー行。NSHostingView でラップして NSMenuItem.view に設定する。
struct DashboardMenuItemView: View {
    let provider: UsageProvider
    let snapshot: UsageSnapshot
    let displayMode: UsageDisplayMode

    var body: some View {
        Button {
            NSWorkspace.shared.open(provider.usageURL)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                headerRow
                windowRows
            }
            .padding(.leading, 17)
            .padding(.trailing, 13)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - ヘッダー行

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(provider.displayName)
                .fontWeight(.semibold)
            Spacer()
            if provider == .githubCopilot {
                Label(copilotResetText, systemImage: "calendar")
            } else {
                Label(primaryRemainingText, systemImage: "clock")
                Label(secondaryResetText, systemImage: "calendar")
            }
        }
        .font(.system(size: 11))
    }

    // MARK: - ウィンドウ行

    @ViewBuilder
    private var windowRows: some View {
        if provider == .githubCopilot {
            if let primary = snapshot.primaryWindow {
                windowRow(label: "mo", window: primary, windowKind: .primary)
            }
        } else {
            if let primary = snapshot.primaryWindow {
                windowRow(label: "5h", window: primary, windowKind: .primary)
            }
            if let secondary = snapshot.secondaryWindow {
                windowRow(label: "1w", window: secondary, windowKind: .secondary)
            }
        }
    }

    private func windowRow(label: String, window: UsageWindow, windowKind: UsageWindowKind) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            UsageLinearBarView(
                provider: provider,
                windowKind: windowKind,
                window: window,
                displayMode: displayMode
            )

            Text(UsagePercentFormatter.formatPercentText(
                displayMode.displayPercent(from: window.usedPercent, window: window)
            ))
            .font(.system(size: 11))
            .frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: - 時間テキスト

    private var primaryRemainingText: String {
        guard let window = snapshot.primaryWindow else { return "--" }
        let remaining = max(0, window.limitWindowSeconds * (1.0 - window.usedPercent / 100.0))
        if remaining >= 3600 {
            return String(format: "menu.dashboard.remainingHours".localized(), remaining / 3600.0)
        }
        return String(format: "menu.dashboard.remainingMinutes".localized(), max(1, Int(remaining) / 60))
    }

    private var secondaryResetText: String {
        guard let window = snapshot.secondaryWindow, let resetAt = window.resetAt else { return "--" }
        return formatResetRelative(resetAt)
    }

    private var copilotResetText: String {
        guard let window = snapshot.primaryWindow, let resetAt = window.resetAt else { return "--" }
        return formatResetRelative(resetAt)
    }

    private func formatResetRelative(_ resetAt: Date) -> String {
        let remaining = resetAt.timeIntervalSinceNow
        if remaining <= 60 {
            return "menu.dashboard.soon".localized()
        } else if remaining >= 86400 {
            return String(format: "menu.dashboard.resetDaysLater".localized(), remaining / 86400.0)
        } else if remaining >= 3600 {
            return String(format: "menu.dashboard.resetHoursLater".localized(), remaining / 3600.0)
        } else {
            return String(format: "menu.dashboard.resetMinutesLater".localized(), max(1, Int(remaining) / 60))
        }
    }
}
