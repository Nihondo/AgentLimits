// MARK: - WidgetUsageModels.swift
// Widget-specific error localization helpers layered on shared models.

import Foundation

/// Localized description for widget-facing snapshot store errors
extension UsageSnapshotStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App Group が利用できません。"
        }
    }
}
