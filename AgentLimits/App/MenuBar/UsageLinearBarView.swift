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

    /// 使用率バーの高さ（ドーナツの outerLineWidth = 8 に相当）
    private let usageBarHeight: CGFloat = 7
    /// ペースメーカーバーの高さ（ドーナツの innerLineWidth = 4 に相当）
    private let pacemakerBarHeight: CGFloat = 4
    /// バー間の縦スペース
    private let verticalSpacing: CGFloat = 2
    /// バーの角丸
    private let cornerRadius: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            usageBar
            // ウィジェット同様、表示モード適用後のペースメーカー進捗が取得できる場合のみ表示
            if displayPacemakerPercent != nil {
                pacemakerBar
            }
        }
    }

    // MARK: - 上段: 使用率バー

    private var usageBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 背景トラック
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.25))

                // 使用済み部分
                if let segments = pacemakerSegments {
                    segmentedFillView(segments: segments, totalWidth: geo.size.width)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(barColor)
                        .frame(width: geo.size.width * usageProgress)
                }
            }
        }
        .frame(height: usageBarHeight)
    }

    /// ペースメーカー超過時のセグメント分け塗り
    @ViewBuilder
    private func segmentedFillView(segments: PacemakerLinearSegments, totalWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // ZStack の幅を totalWidth に固定しないと offset した矩形が clipShape でクリップされる
            Color.clear.frame(width: totalWidth, height: usageBarHeight)
            // normal: 0..normalEnd（メインカラー）
            if segments.normalEnd > 0 {
                Rectangle()
                    .fill(barColor)
                    .frame(width: totalWidth * segments.normalEnd, height: usageBarHeight)
            }
            // warning: warningStart..min(dangerStart, totalEnd)（ウィジェット同様に totalEnd でクリップ）
            let warningEnd = min(segments.dangerStart, segments.totalEnd)
            if warningEnd > segments.warningStart {
                Rectangle()
                    .fill(pacemakerWarningColor)
                    .frame(width: totalWidth * (warningEnd - segments.warningStart), height: usageBarHeight)
                    .offset(x: totalWidth * segments.warningStart)
            }
            // danger: dangerStart..totalEnd（赤）
            if segments.totalEnd > segments.dangerStart {
                Rectangle()
                    .fill(pacemakerDangerColor)
                    .frame(width: totalWidth * (segments.totalEnd - segments.dangerStart), height: usageBarHeight)
                    .offset(x: totalWidth * segments.dangerStart)
            }
        }
        .frame(width: totalWidth, height: usageBarHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // MARK: - 下段: ペースメーカーバー

    private var pacemakerBar: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let count = divisionCount
            let gapWidth = count > 1 ? totalWidth * LinearDivisionParams.gapFraction : 0
            let segmentWidth = (totalWidth - gapWidth * CGFloat(max(0, count - 1))) / CGFloat(count)

            HStack(spacing: gapWidth) {
                ForEach(0..<count, id: \.self) { index in
                    pacemakerSegmentView(index: index, width: segmentWidth)
                }
            }
        }
        .frame(height: pacemakerBarHeight)
    }

    /// 1セグメントぶんのペースメーカーバー（背景＋進捗塗り）
    private func pacemakerSegmentView(index: Int, width: CGFloat) -> some View {
        let count = divisionCount
        let segStart = Double(index) / Double(count)
        let segEnd = Double(index + 1) / Double(count)
        let progress = pacemakerProgress
        let fillRatio: Double
        if progress <= segStart {
            fillRatio = 0
        } else if progress >= segEnd {
            fillRatio = 1
        } else {
            fillRatio = (progress - segStart) / (segEnd - segStart)
        }

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.2))
            if fillRatio > 0 {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(pacemakerRingColor)
                    .frame(width: width * fillRatio)
            }
        }
        .frame(width: width, height: pacemakerBarHeight)
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
        guard PacemakerRingWarningSettings.isWarningEnabled() else { return nil }
        guard displayMode != .remaining else { return nil }
        guard let window else { return nil }
        // 使用率閾値で色が変わっているとき（orange/red）はセグメント分け表示しない
        if let level = AppUsageColorResolver.barLevel(
            usedPercent: window.usedPercent,
            provider: provider,
            windowKind: windowKind
        ), level != .green {
            return nil
        }
        guard let pacemakerPercent = window.calculatePacemakerPercent() else { return nil }
        let warningDelta = PacemakerThresholdSettings.loadWarningDelta()
        let dangerDelta = PacemakerThresholdSettings.loadDangerDelta()
        guard window.usedPercent > pacemakerPercent + warningDelta else { return nil }

        let totalEnd = usageProgress
        let warningStart = clamp((pacemakerPercent + warningDelta) / 100)
        let dangerStart = max(warningStart, clamp((pacemakerPercent + dangerDelta) / 100))
        let normalEnd = min(totalEnd, warningStart)
        return PacemakerLinearSegments(
            normalEnd: normalEnd,
            warningStart: warningStart,
            dangerStart: dangerStart,
            totalEnd: totalEnd
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

/// 使用率バーをペースメーカー超過時に色分けするためのセグメント情報。
private struct PacemakerLinearSegments {
    let normalEnd: Double
    let warningStart: Double
    let dangerStart: Double
    let totalEnd: Double
}

/// 線形バーの分割パラメータ（ドーナツの RingDivisionParams 線形版）。
enum LinearDivisionParams {
    /// セグメント間ギャップが全長に占める割合
    static let gapFraction: Double = 0.015
}
