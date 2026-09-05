// MARK: - UsageRingGaugeView.swift
// Shared ring gauge drawing (outer progress ring + pacemaker division ring + center label)
// used by both the built-in usage widgets and the custom usage widget so their designs stay identical.

import SwiftUI

/// ペースメーカー超過時にアウターリングを塗り分けるための区間情報です。
struct PacemakerRingSegments {
    let normalEnd: Double
    let warningStart: Double
    let dangerStart: Double
    let totalEnd: Double

    /// ペースメーカー超過分の警告/危険セグメントを算出します。表示対象でなければnilを返します。
    static func compute(
        usedPercent: Double,
        pacemakerPercent: Double?,
        progress: Double,
        isEligible: Bool
    ) -> PacemakerRingSegments? {
        guard isEligible, let pacemakerPercent else { return nil }
        let warningDelta = PacemakerThresholdSettings.loadWarningDelta()
        let dangerDelta = PacemakerThresholdSettings.loadDangerDelta()
        guard usedPercent > pacemakerPercent + warningDelta else { return nil }

        let totalEnd = clampProgress(progress)
        let warningStart = clampProgress((pacemakerPercent + warningDelta) / 100)
        let dangerStart = max(warningStart, clampProgress((pacemakerPercent + dangerDelta) / 100))
        let normalEnd = min(totalEnd, warningStart)
        return PacemakerRingSegments(normalEnd: normalEnd, warningStart: warningStart, dangerStart: dangerStart, totalEnd: totalEnd)
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// 使用率カラーリングが警告/危険を示している場合に、ペースメーカー警告セグメントの表示を抑制するかどうかを判定します。
enum WidgetRingWarningGate {
    static func isBlockedByStatusColor(usedPercent: Double, thresholds: UsageStatusThresholds) -> Bool {
        let defaults = AppGroupDefaults.shared
        guard defaults?.bool(forKey: UsageColorKeys.donutUseStatus) ?? false else { return false }
        let level = UsageStatusLevelResolver.level(
            for: usedPercent,
            isRemainingMode: false,
            warningThreshold: thresholds.warningPercent,
            dangerThreshold: thresholds.dangerPercent
        )
        return level != .green
    }
}

/// 内側ペースメーカーリングの等分ギャップ計算をまとめたヘルパーです。
enum RingDivisionParams {
    /// 1つのギャップが占める割合（全周=1.0）
    static let gapFraction: Double = 0.015

    /// N等分のギャップ範囲を返します。区切りは (N-1) 個です。
    static func gapRanges(count: Int) -> [(start: Double, end: Double)] {
        guard count > 1 else { return [] }
        let segmentSize = 1.0 / Double(count)
        let halfGap = gapFraction / 2.0
        return (1..<count).map { i in
            let center = segmentSize * Double(i)
            return (start: center - halfGap, end: center + halfGap)
        }
    }

    /// 全周 (0...1) からギャップを除いた可視セグメント一覧を返します。
    static func trackSegmentRanges(_ gaps: [(start: Double, end: Double)]) -> [(start: Double, end: Double)] {
        var result: [(start: Double, end: Double)] = []
        var cursor: Double = 0
        for gap in gaps.sorted(by: { $0.start < $1.start }) {
            if gap.start > cursor {
                result.append((start: cursor, end: gap.start))
            }
            cursor = gap.end
        }
        if cursor < 1.0 {
            result.append((start: cursor, end: 1.0))
        }
        return result
    }

    /// (start, end) 範囲をギャップで分割し、可視サブセグメントを返します。
    static func clipToGaps(
        from start: Double,
        to end: Double,
        gaps: [(start: Double, end: Double)]
    ) -> [(start: Double, end: Double)] {
        guard !gaps.isEmpty, end > start else {
            return [(start: start, end: end)]
        }
        var result: [(start: Double, end: Double)] = []
        var cursor = start
        for gap in gaps.sorted(by: { $0.start < $1.start }) {
            guard gap.end > start, gap.start < end else { continue }
            let gapStart = max(gap.start, start)
            let gapEnd = min(gap.end, end)
            if gapStart > cursor {
                result.append((start: cursor, end: gapStart))
            }
            cursor = gapEnd
        }
        if cursor < end {
            result.append((start: cursor, end: end))
        }
        return result
    }
}

/// ドーナツ列のサイズ計算（利用可能幅に応じて縮小）を共通化するヘルパーです。
/// 組み込みWidgetとカスタムWidgetで同じ計算式を使い、スケールのズレを防ぎます。
enum WidgetDonutLayout {
    static let targetDonutSize: CGFloat = 66
    static let columnSpacing: CGFloat = 12
    static let detailColumnWidth: CGFloat = 170
    static let contentHeight: CGFloat = 100
    static let contentTopPadding: CGFloat = 6

    /// ドーナツと使用率ラベルを含む列の共通高さを返します。
    static func columnHeight(donutSize: CGFloat) -> CGFloat {
        donutSize + 30
    }

    /// 利用可能幅と列数から、targetDonutSizeを超えないドーナツサイズを算出します。
    static func donutSize(availableWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return targetDonutSize }
        let totalSpacing = columnSpacing * CGFloat(max(0, columnCount - 1))
        let availableDonutSize = max(0, (availableWidth - totalSpacing) / CGFloat(columnCount))
        return min(targetDonutSize, availableDonutSize)
    }
}

/// 円形使用率ゲージ（アウターリング + ペースメーカー分割インナーリング + 中央ラベル）を描画する共通ビューです。
/// 組み込みWidgetとカスタムWidgetの見た目を揃えるために両方から利用します。
struct UsageRingGaugeView: View {
    let centerLabel: String
    let progress: Double
    let ringColor: Color
    let pacemakerSegments: PacemakerRingSegments?
    let pacemakerProgress: Double?
    let pacemakerRingColor: Color
    let pacemakerWarningColor: Color
    let pacemakerDangerColor: Color
    let divisionCount: Int
    let size: CGFloat
    var accessibilityPercentText: String

    private let outerLineWidth: CGFloat = 8
    private let innerLineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: outerLineWidth)
            if let segments = pacemakerSegments {
                ringSegmentView(from: 0, to: segments.normalEnd, color: ringColor)
                ringSegmentView(
                    from: segments.warningStart,
                    to: min(segments.dangerStart, segments.totalEnd),
                    color: pacemakerWarningColor
                )
                ringSegmentView(from: segments.dangerStart, to: segments.totalEnd, color: pacemakerDangerColor)
            } else {
                ringSegmentView(from: 0, to: progress, color: ringColor)
            }
            if let pacemakerProgress {
                let gaps = RingDivisionParams.gapRanges(count: divisionCount)
                ForEach(Array(RingDivisionParams.trackSegmentRanges(gaps).enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.start, to: seg.end)
                        .stroke(style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .foregroundStyle(.quaternary.opacity(0.5))
                        .padding(outerLineWidth)
                }
                ForEach(Array(RingDivisionParams.clipToGaps(from: 0, to: pacemakerProgress, gaps: gaps).enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.start, to: seg.end)
                        .stroke(style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .foregroundStyle(pacemakerRingColor)
                        .padding(outerLineWidth)
                }
            }
            Text(centerLabel)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .frame(maxWidth: size * 0.72)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(centerLabel)
        .accessibilityValue(accessibilityPercentText)
    }

    @ViewBuilder
    private func ringSegmentView(from start: Double, to end: Double, color: Color) -> some View {
        if end > start {
            Circle()
                .trim(from: start, to: end)
                .stroke(style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .foregroundStyle(color)
        }
    }
}
