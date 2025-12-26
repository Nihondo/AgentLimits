// MARK: - LoginItemManager.swift
// Manages app registration as a login item for auto-start at login.
// Uses SMAppService (macOS 13+) for modern login item management.

import Combine
import Foundation
import ServiceManagement

/// Manages app registration as a login item
@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var statusMessage: String?

    private init() {
        updateStatus()
    }

    /// Checks and updates the current login item status
    func updateStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
        statusMessage = statusDescription(for: SMAppService.mainApp.status)
    }

    /// Enables or disables the app as a login item
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            updateStatus()
        } catch {
            NSLog("LoginItemManager: Failed to %@ login item: %@",
                  enabled ? "register" : "unregister",
                  error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    /// Returns a human-readable description of the login item status
    private func statusDescription(for status: SMAppService.Status) -> String? {
        switch status {
        case .notRegistered:
            return nil
        case .enabled:
            return nil
        case .requiresApproval:
            return "loginItem.requiresApproval".localized()
        case .notFound:
            return "loginItem.notFound".localized()
        @unknown default:
            return nil
        }
    }
}
