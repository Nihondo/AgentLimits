// MARK: - WidgetUsageModels.swift
// Widget-specific error localization helpers layered on shared models.

import Foundation

/// Localized description for widget-facing snapshot store errors.
/// Provides user-friendly error messages for widget display.
extension UsageSnapshotStoreError: LocalizedError {
    var errorDescription: String? {
        UsageSnapshotStoreErrorMessageResolver.resolveMessage(
            for: self,
            localize: { WidgetLanguageHelper.localizedString($0) },
            includeUnderlying: false
        )
    }
}
