// MARK: - UsageColorSettings.swift
// Shared color settings for usage UI (menu bar + widgets).

import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// UserDefaults keys for usage color customization.
enum UsageColorKeys {
    static let donut = "usage_color_donut"
    static let donutUseStatus = "usage_color_donut_use_status"
    static let statusGreen = "usage_color_green"
    static let statusOrange = "usage_color_orange"
    static let statusRed = "usage_color_red"
    static let pacemakerRing = "usage_color_pacemaker_ring"
    static let pacemakerStatusOrange = "usage_color_pacemaker_status_orange"
    static let pacemakerStatusRed = "usage_color_pacemaker_status_red"
}

/// Helpers for storing and resolving usage colors from App Group defaults.
enum UsageColorSettings {
    /// Loads the donut ring color (widget only).
    static func loadDonutColor() -> Color {
        loadColor(forKey: UsageColorKeys.donut, defaultColor: .accentColor)
    }

    /// Returns whether donut colors should follow usage status.
    static func loadDonutUseStatus() -> Bool {
        let defaults = AppGroupDefaults.shared
        return defaults?.bool(forKey: UsageColorKeys.donutUseStatus) ?? false
    }

    /// Loads the green status color.
    static func loadStatusGreenColor() -> Color {
        loadColor(forKey: UsageColorKeys.statusGreen, defaultColor: .green)
    }

    /// Loads the orange status color.
    static func loadStatusOrangeColor() -> Color {
        loadColor(forKey: UsageColorKeys.statusOrange, defaultColor: .orange)
    }

    /// Loads the red status color.
    static func loadStatusRedColor() -> Color {
        loadColor(forKey: UsageColorKeys.statusRed, defaultColor: .red)
    }

    /// Saves the donut ring color override.
    static func saveDonutColor(_ color: Color) {
        saveColor(color, forKey: UsageColorKeys.donut)
    }

    /// Saves the usage-status flag for donut coloring.
    static func saveDonutUseStatus(_ value: Bool) {
        let defaults = AppGroupDefaults.shared
        defaults?.set(value, forKey: UsageColorKeys.donutUseStatus)
    }

    /// Saves the green status color override.
    static func saveStatusGreenColor(_ color: Color) {
        saveColor(color, forKey: UsageColorKeys.statusGreen)
    }

    /// Saves the orange status color override.
    static func saveStatusOrangeColor(_ color: Color) {
        saveColor(color, forKey: UsageColorKeys.statusOrange)
    }

    /// Saves the red status color override.
    static func saveStatusRedColor(_ color: Color) {
        saveColor(color, forKey: UsageColorKeys.statusRed)
    }

    /// Loads the pacemaker ring color (widget inner donut).
    static func loadPacemakerRingColor() -> Color {
        loadColor(forKey: UsageColorKeys.pacemakerRing, defaultColor: Color.blue.opacity(0.6))
    }

    /// Loads the pacemaker status color for warning indicator.
    static func loadPacemakerStatusOrangeColor() -> Color {
        loadColor(forKey: UsageColorKeys.pacemakerStatusOrange, defaultColor: .orange)
    }

    /// Loads the pacemaker status color for danger indicator.
    static func loadPacemakerStatusRedColor() -> Color {
        loadColor(forKey: UsageColorKeys.pacemakerStatusRed, defaultColor: .red)
    }

    /// Saves the pacemaker ring color override.
    static func savePacemakerRingColor(_ color: Color) {
        saveColor(color, forKey: UsageColorKeys.pacemakerRing)
    }

    /// Saves the pacemaker status color override for warning indicator.
    static func savePacemakerStatusOrangeColor(_ color: Color) {
        saveColor(color, forKey: UsageColorKeys.pacemakerStatusOrange)
    }

    /// Saves the pacemaker status color override for danger indicator.
    static func savePacemakerStatusRedColor(_ color: Color) {
        saveColor(color, forKey: UsageColorKeys.pacemakerStatusRed)
    }

    /// Clears stored overrides to restore defaults.
    static func resetToDefaults() {
        let defaults = AppGroupDefaults.shared
        defaults?.removeObject(forKey: UsageColorKeys.donut)
        defaults?.removeObject(forKey: UsageColorKeys.donutUseStatus)
        defaults?.removeObject(forKey: UsageColorKeys.statusGreen)
        defaults?.removeObject(forKey: UsageColorKeys.statusOrange)
        defaults?.removeObject(forKey: UsageColorKeys.statusRed)
        defaults?.removeObject(forKey: UsageColorKeys.pacemakerRing)
        defaults?.removeObject(forKey: UsageColorKeys.pacemakerStatusOrange)
        defaults?.removeObject(forKey: UsageColorKeys.pacemakerStatusRed)
    }

    /// Clears stored overrides for usage status colors.
    static func resetUsageStatusColors() {
        let defaults = AppGroupDefaults.shared
        defaults?.removeObject(forKey: UsageColorKeys.donut)
        defaults?.removeObject(forKey: UsageColorKeys.donutUseStatus)
        defaults?.removeObject(forKey: UsageColorKeys.statusGreen)
        defaults?.removeObject(forKey: UsageColorKeys.statusOrange)
        defaults?.removeObject(forKey: UsageColorKeys.statusRed)
    }

    /// Clears stored overrides for pacemaker colors.
    static func resetPacemakerColors() {
        let defaults = AppGroupDefaults.shared
        defaults?.removeObject(forKey: UsageColorKeys.pacemakerRing)
        defaults?.removeObject(forKey: UsageColorKeys.pacemakerStatusOrange)
        defaults?.removeObject(forKey: UsageColorKeys.pacemakerStatusRed)
    }

    private static func loadColor(forKey key: String, defaultColor: Color) -> Color {
        let defaults = AppGroupDefaults.shared
        let storedValue = defaults?.string(forKey: key)
        return ColorHexCodec.resolveColor(from: storedValue, defaultColor: defaultColor)
    }

    private static func saveColor(_ color: Color, forKey key: String) {
        guard let hexValue = ColorHexCodec.hexString(from: color) else { return }
        let defaults = AppGroupDefaults.shared
        defaults?.set(hexValue, forKey: key)
    }
}

/// Converts between Color and hex strings for persistence.
enum ColorHexCodec {
    /// Resolves a stored hex string into Color or returns the default.
    static func resolveColor(from storedValue: String?, defaultColor: Color) -> Color {
        guard let storedValue, let color = color(from: storedValue) else {
            return defaultColor
        }
        return color
    }

    /// Parses a hex string like "#RRGGBB" or "#RRGGBBAA".
    static func color(from hex: String) -> Color? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let length = normalized.count
        guard length == 6 || length == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: normalized).scanHexInt64(&value) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if length == 6 {
            red = Double((value >> 16) & 0xFF) / 255.0
            green = Double((value >> 8) & 0xFF) / 255.0
            blue = Double(value & 0xFF) / 255.0
            alpha = 1.0
        } else {
            red = Double((value >> 24) & 0xFF) / 255.0
            green = Double((value >> 16) & 0xFF) / 255.0
            blue = Double((value >> 8) & 0xFF) / 255.0
            alpha = Double(value & 0xFF) / 255.0
        }

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Encodes a Color into a "#RRGGBBAA" hex string.
    static func hexString(from color: Color) -> String? {
        #if canImport(AppKit)
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        let alpha = Int(round(nsColor.alphaComponent * 255))
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        #elseif canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255)),
            Int(round(alpha * 255))
        )
        #else
        return nil
        #endif
    }
}

// MARK: - Pacemaker Threshold Settings

/// Settings for enabling or disabling pacemaker ring warning segments.
enum PacemakerRingWarningSettings {
    static let defaultEnabled = true

    static func isWarningEnabled() -> Bool {
        let defaults = AppGroupDefaults.shared
        guard defaults?.object(forKey: SharedUserDefaultsKeys.pacemakerRingWarningEnabled) != nil else {
            return defaultEnabled
        }
        return defaults?.bool(forKey: SharedUserDefaultsKeys.pacemakerRingWarningEnabled) ?? defaultEnabled
    }
}

/// UserDefaults keys for pacemaker mode threshold customization.
enum PacemakerThresholdKeys {
    static let warningDelta = "pacemaker_warning_delta"
    static let dangerDelta = "pacemaker_danger_delta"
}

/// Settings for pacemaker mode color thresholds (excess percentage).
enum PacemakerThresholdSettings {
    /// Default warning delta (orange when exceeding pacemaker by this amount)
    static let defaultWarningDelta: Double = 0

    /// Default danger delta (red when exceeding pacemaker by this amount)
    static let defaultDangerDelta: Double = 10

    /// Loads the warning delta (excess % to trigger orange).
    static func loadWarningDelta() -> Double {
        let defaults = AppGroupDefaults.shared
        let value = defaults?.object(forKey: PacemakerThresholdKeys.warningDelta) as? Double
        return value ?? defaultWarningDelta
    }

    /// Loads the danger delta (excess % to trigger red).
    static func loadDangerDelta() -> Double {
        let defaults = AppGroupDefaults.shared
        let value = defaults?.object(forKey: PacemakerThresholdKeys.dangerDelta) as? Double
        return value ?? defaultDangerDelta
    }

    /// Saves the warning delta.
    static func saveWarningDelta(_ value: Double) {
        let defaults = AppGroupDefaults.shared
        defaults?.set(value, forKey: PacemakerThresholdKeys.warningDelta)
    }

    /// Saves the danger delta.
    static func saveDangerDelta(_ value: Double) {
        let defaults = AppGroupDefaults.shared
        defaults?.set(value, forKey: PacemakerThresholdKeys.dangerDelta)
    }

    /// Resets to default values.
    static func resetToDefaults() {
        let defaults = AppGroupDefaults.shared
        defaults?.removeObject(forKey: PacemakerThresholdKeys.warningDelta)
        defaults?.removeObject(forKey: PacemakerThresholdKeys.dangerDelta)
    }
}
