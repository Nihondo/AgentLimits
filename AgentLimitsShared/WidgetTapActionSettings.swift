// MARK: - WidgetTapActionSettings.swift
// Settings for widget tap action (open website or refresh data).

import Foundation

// MARK: - Widget Tap Action

/// Action to perform when a widget is tapped
enum WidgetTapAction: String, Codable, CaseIterable, Identifiable {
    case openWebsite   // Open the usage website (default)
    case refreshData   // Refresh data immediately

    var id: String { rawValue }

    /// Localization key for UI display
    var localizationKey: String {
        switch self {
        case .openWebsite: return "widgetTapAction.openWebsite"
        case .refreshData: return "widgetTapAction.refreshData"
        }
    }
}

// MARK: - Widget Tap Action Store

/// Persistence store for widget tap action setting
enum WidgetTapActionStore {
    private static let key = "widget_tap_action"

    /// Loads the current widget tap action setting
    static func loadAction() -> WidgetTapAction {
        guard let defaults = AppGroupDefaults.shared,
              let rawValue = defaults.string(forKey: key),
              let action = WidgetTapAction(rawValue: rawValue) else {
            return .openWebsite
        }
        return action
    }

    /// Saves the widget tap action setting
    static func saveAction(_ action: WidgetTapAction) {
        AppGroupDefaults.shared?.set(action.rawValue, forKey: key)
    }
}
