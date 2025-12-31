// MARK: - HeatmapColors.swift
// Color definitions for heatmap visualization based on GitHub contributions graph.

import SwiftUI
import WidgetKit

// MARK: - Heatmap Level

/// Heatmap color levels based on quartile distribution.
/// Inspired by GitHub contributions graph color scheme.
enum HeatmapLevel: Int, CaseIterable {
    /// No usage (0 tokens)
    case none = 0
    /// Bottom 25% of usage
    case firstQuartile = 1
    /// 25-50% of usage
    case secondQuartile = 2
    /// 50-75% of usage
    case thirdQuartile = 3
    /// Top 25% of usage (highest)
    case fourthQuartile = 4

    /// Returns the color for this level (full color mode)
    var color: Color {
        switch self {
        case .none:
            return Color(hex: 0x151b23)
        case .firstQuartile:
            return Color(hex: 0x033a16)
        case .secondQuartile:
            return Color(hex: 0x196c2e)
        case .thirdQuartile:
            return Color(hex: 0x2ea043)
        case .fourthQuartile:
            return Color(hex: 0x56d364)
        }
    }

    /// Returns opacity for accented rendering mode (desktop pinned widgets).
    /// Uses white color with varying opacity to show intensity.
    var accentedOpacity: Double {
        switch self {
        case .none:
            return 0.1
        case .firstQuartile:
            return 0.3
        case .secondQuartile:
            return 0.5
        case .thirdQuartile:
            return 0.7
        case .fourthQuartile:
            return 1.0
        }
    }

    /// Returns the appropriate color based on widget rendering mode.
    /// - Parameter renderingMode: The current widget rendering mode
    /// - Returns: Color with appropriate styling for the mode
    @MainActor
    func color(for renderingMode: WidgetRenderingMode) -> Color {
        if renderingMode == .accented {
            // Desktop pinned: use white with varying opacity
            return Color.white.opacity(accentedOpacity)
        } else {
            // Normal widget (fullColor, vibrant, etc.): use full color
            return color
        }
    }
}

// MARK: - Color Extension

extension Color {
    /// Creates a Color from a hex value (0xRRGGBB)
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
