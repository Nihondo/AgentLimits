// MARK: - UsageLinearBarView.swift
// メニューバー ダッシュボード用の線形プログレスバー（ドーナツリングの線形版）。
// 上段: 使用率バー（ペースメーカー超過時はセグメント色分け）
// 下段: ペースメーカーバー（5h=5分割、週次=7分割、月次=分割なし、ギャップ付き）

import SwiftUI

/// 1ウィンドウ分の使用率/ペースメーカーを線形バーで描画する。
struct UsageLinearBarView: View {
    let provider: UsageProvider
    let windowKind: UsageWindowKind
    let window: UsageWindow?
    let displayMode: UsageDisplayMode

    var body: some View {
        UsageLinearGaugeView(
            usageProgress: usageProgress,
            barColor: barColor,
            pacemakerSegments: pacemakerSegments,
            pacemakerProgress: displayPacemakerPercent != nil ? pacemakerProgress : nil,
            pacemakerRingColor: pacemakerRingColor,
            pacemakerWarningColor: pacemakerWarningColor,
            pacemakerDangerColor: pacemakerDangerColor,
            divisionCount: divisionCount
        )
    }

    // MARK: - 進捗値

    private var usageProgress: Double {
        guard let window else { return 0 }
        // ウィジェット同様、displayMode 適用後の値を使う（残りモードでバーとテキストを一致させる）
        return clamp(displayMode.displayPercent(from: window.usedPercent, window: window) / 100)
    }

    private var pacemakerProgress: Double {
        guard let percent = displayPacemakerPercent else { return 0 }
        return clamp(percent / 100)
    }

    private var displayPacemakerPercent: Double? {
        window?.displayPacemakerPercent(for: displayMode.makeDisplayModeRaw())
    }

    private var divisionCount: Int {
        window?.pacemakerDivisionCount ?? (windowKind == .primary ? 5 : 7)
    }

    /// ペースメーカー超過時のセグメント情報。超過していない場合は nil。
    private var pacemakerSegments: PacemakerLinearSegments? {
        guard let window else { return nil }
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: provider, windowKind: windowKind)
        let isEligible = PacemakerRingWarningSettings.isWarningEnabled()
            && displayMode != .remaining
            && !LinearWarningGate.isBlockedByStatusColor(usedPercent: window.usedPercent, thresholds: thresholds)
        return PacemakerLinearSegments.compute(
            usedPercent: window.usedPercent,
            pacemakerPercent: window.calculatePacemakerPercent(),
            progress: usageProgress,
            isEligible: isEligible
        )
    }

    // MARK: - 色

    private var barColor: Color {
        AppUsageColorResolver.barColor(
            usedPercent: window?.usedPercent,
            provider: provider,
            windowKind: windowKind
        )
    }

    private var pacemakerRingColor: Color {
        UsageColorSettings.loadPacemakerRingColor()
    }

    private var pacemakerWarningColor: Color {
        UsageColorSettings.loadPacemakerStatusOrangeColor()
    }

    private var pacemakerDangerColor: Color {
        UsageColorSettings.loadPacemakerStatusRedColor()
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
