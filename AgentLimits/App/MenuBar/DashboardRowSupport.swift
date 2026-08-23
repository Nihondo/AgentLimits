// MARK: - DashboardRowSupport.swift
// メニューバーダッシュボード行（組み込み/カスタム共通）で使う見た目のパーツ。
// ヘッダーの残り時間ラベル、ホバー時のハイライトスタイルをここに集約し、
// 組み込みサービスとカスタムサービスのダッシュボード行の見た目を一致させる。

import SwiftUI

/// ダッシュボード行のヘッダー右側に表示する残り時間/リセット時刻ラベル。
/// ウィンドウが1つなら「リセット時刻」のみ、2つなら「残り時間 + 2つ目のリセット時刻」を表示する。
struct DashboardResetLabels: View {
    let resetDates: [Date?]

    var body: some View {
        if resetDates.count <= 1 {
            Label(DashboardTimeFormatting.resetRelativeText(resetDates.first ?? nil), systemImage: "calendar")
        } else {
            Label(DashboardTimeFormatting.remainingText(until: resetDates.first ?? nil), systemImage: "clock")
            Label(DashboardTimeFormatting.resetRelativeText(resetDates.last ?? nil), systemImage: "calendar")
        }
    }
}

/// ダッシュボード行のヘッダーで使う時間テキストのフォーマットをまとめたユーティリティ。
enum DashboardTimeFormatting {
    static func remainingText(until resetAt: Date?) -> String {
        guard let resetAt else { return "--" }
        let remaining = max(0, resetAt.timeIntervalSinceNow)
        if remaining >= 3600 {
            return String(format: "menu.dashboard.remainingHours".localized(), remaining / 3600.0)
        }
        return String(format: "menu.dashboard.remainingMinutes".localized(), max(1, Int(remaining) / 60))
    }

    static func resetRelativeText(_ resetAt: Date?) -> String {
        guard let resetAt else { return "--" }
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

/// ダッシュボード行のホバー時ハイライト（NSVisualEffectViewのmaterial選択に近づけた配色）を共通化するモディファイア。
struct DashboardRowStyle: ViewModifier {
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? menuHighlightColor : .clear)
                    .padding(.horizontal, 5)
            )
    }

    // NSVisualEffectView のmaterial selectionはアクセントカラーより暗く合成されるため、
    // ダークモード時のみHSB空間で明度を下げてネイティブに近づける
    private var menuHighlightColor: Color {
        guard colorScheme == .dark,
              let rgb = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) else {
            return Color.accentColor
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(NSColor(hue: h, saturation: s, brightness: b * 0.78, alpha: a))
    }
}

extension View {
    /// ダッシュボード行の共通ホバースタイル（文字色反転 + ハイライト背景）を適用する。
    func dashboardRowStyle(isHovered: Bool) -> some View {
        modifier(DashboardRowStyle(isHovered: isHovered))
    }
}

/// ダッシュボード行の線形使用率バー（使用率バー + ペースメーカー分割バー）を描画する共通ビュー。
/// 組み込み/カスタム双方の `UsageLinearBarView` 相当の実装から共有し、見た目を一致させる。
struct UsageLinearGaugeView: View {
    let usageProgress: Double
    let barColor: Color
    let pacemakerSegments: PacemakerLinearSegments?
    let pacemakerProgress: Double?
    let pacemakerRingColor: Color
    let pacemakerWarningColor: Color
    let pacemakerDangerColor: Color
    let divisionCount: Int

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
            if let pacemakerProgress {
                pacemakerBar(progress: pacemakerProgress)
            }
        }
    }

    // MARK: - 上段: 使用率バー

    private var usageBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.25))
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

    @ViewBuilder
    private func segmentedFillView(segments: PacemakerLinearSegments, totalWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: totalWidth, height: usageBarHeight)
            if segments.normalEnd > 0 {
                Rectangle()
                    .fill(barColor)
                    .frame(width: totalWidth * segments.normalEnd, height: usageBarHeight)
            }
            let warningEnd = min(segments.dangerStart, segments.totalEnd)
            if warningEnd > segments.warningStart {
                Rectangle()
                    .fill(pacemakerWarningColor)
                    .frame(width: totalWidth * (warningEnd - segments.warningStart), height: usageBarHeight)
                    .offset(x: totalWidth * segments.warningStart)
            }
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

    private func pacemakerBar(progress: Double) -> some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let count = max(1, divisionCount)
            let gapWidth = count > 1 ? totalWidth * LinearDivisionParams.gapFraction : 0
            let segmentWidth = (totalWidth - gapWidth * CGFloat(max(0, count - 1))) / CGFloat(count)

            HStack(spacing: gapWidth) {
                ForEach(0..<count, id: \.self) { index in
                    pacemakerSegmentView(index: index, width: segmentWidth, count: count, progress: progress)
                }
            }
        }
        .frame(height: pacemakerBarHeight)
    }

    private func pacemakerSegmentView(index: Int, width: CGFloat, count: Int, progress: Double) -> some View {
        let segStart = Double(index) / Double(count)
        let segEnd = Double(index + 1) / Double(count)
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
}

/// 使用率バーをペースメーカー超過時に色分けするためのセグメント情報。
struct PacemakerLinearSegments {
    let normalEnd: Double
    let warningStart: Double
    let dangerStart: Double
    let totalEnd: Double

    /// ペースメーカー超過分の警告/危険セグメントを算出する。表示対象でなければnilを返す。
    static func compute(
        usedPercent: Double,
        pacemakerPercent: Double?,
        progress: Double,
        isEligible: Bool
    ) -> PacemakerLinearSegments? {
        guard isEligible, let pacemakerPercent else { return nil }
        let warningDelta = PacemakerThresholdSettings.loadWarningDelta()
        let dangerDelta = PacemakerThresholdSettings.loadDangerDelta()
        guard usedPercent > pacemakerPercent + warningDelta else { return nil }

        let totalEnd = clampProgress(progress)
        let warningStart = clampProgress((pacemakerPercent + warningDelta) / 100)
        let dangerStart = max(warningStart, clampProgress((pacemakerPercent + dangerDelta) / 100))
        let normalEnd = min(totalEnd, warningStart)
        return PacemakerLinearSegments(normalEnd: normalEnd, warningStart: warningStart, dangerStart: dangerStart, totalEnd: totalEnd)
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// 使用率カラーリングが警告/危険を示している場合に、ペースメーカー警告セグメントの表示を抑制するかどうかを判定する。
enum LinearWarningGate {
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

/// 線形バーの分割パラメータ（ドーナツの RingDivisionParams 線形版）。
enum LinearDivisionParams {
    /// セグメント間ギャップが全長に占める割合
    static let gapFraction: Double = 0.015
}
