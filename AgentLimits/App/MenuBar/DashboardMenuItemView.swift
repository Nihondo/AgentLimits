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

    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(provider.usageURL)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                headerRow
                windowRows
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

    // MARK: - ヘッダー行

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(provider.displayName)
                .fontWeight(.semibold)
            Spacer()
            DashboardResetLabels(resetDates: headerResetDates)
        }
        .font(.system(size: 11))
    }

    private var headerResetDates: [Date?] {
        snapshot.isSingleMonthlyWindow
            ? [snapshot.primaryWindow?.resetAt]
            : [snapshot.primaryWindow?.resetAt, snapshot.secondaryWindow?.resetAt]
    }

    // MARK: - ウィンドウ行

    // ウィンドウ未取得時（ログイン直後など）も「これから開始する枠」がわかるよう、
    // データが無くてもラベル/プレースホルダー行は表示する。
    @ViewBuilder
    private var windowRows: some View {
        if snapshot.isSingleMonthlyWindow {
            windowRow(label: "mo", window: snapshot.primaryWindow, windowKind: .primary)
        } else {
            windowRow(label: "5h", window: snapshot.primaryWindow, windowKind: .primary)
            windowRow(label: "1w", window: snapshot.secondaryWindow, windowKind: .secondary)
        }
    }

    private func windowRow(label: String, window: UsageWindow?, windowKind: UsageWindowKind) -> some View {
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
                window.map { displayMode.displayPercent(from: $0.usedPercent, window: $0) }
            ))
            .font(.system(size: 11))
            .frame(width: 38, alignment: .trailing)
        }
    }
}
