// MARK: - AgentLimitsApp.swift
// Main application entry point for AgentLimits menu bar app.
// Provides menu bar UI, settings window, and deep link handling.

import SwiftUI
import AppKit

// MARK: - Deep Link Handling

/// Handles agentlimits:// URL scheme for widget tap actions
private enum DeepLinkHandler {
    /// Handles widget tap action based on user settings
    @MainActor
    static func handleURL(_ url: URL) {
        guard url.scheme == "agentlimits",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let providerValue = components.queryItems?.first { $0.name == "provider" }?.value

        switch url.host {
        case "open-usage":
            guard let providerValue,
                  let provider = UsageProvider(rawValue: providerValue) else { return }
            performTapAction(
                openURL: { provider.usageURL },
                refresh: { await AppSharedState.shared.viewModel.refreshNow(for: provider) }
            )
        case "open-token-usage":
            guard let providerValue,
                  let provider = TokenUsageProvider(rawValue: providerValue) else { return }
            performTapAction(
                openURL: { CCUsageLinks.siteURL },
                refresh: { await AppSharedState.shared.tokenUsageViewModel.refreshNow(for: provider) }
            )
        case "open-custom-usage":
            guard let providerValue,
                  let service = AppSharedState.shared.customUsageViewModel.serviceStore
                    .service(providerID: providerValue) else {
                openCustomUsageSettings(providerID: providerValue)
                return
            }
            switch WidgetTapActionStore.loadAction() {
            case .openWebsite:
                if let websiteURL = service.websiteURL {
                    NSWorkspace.shared.open(websiteURL)
                } else {
                    openCustomUsageSettings(providerID: providerValue)
                }
            case .refreshData:
                Task {
                    await AppSharedState.shared.customUsageViewModel.refresh(providerID: providerValue)
                }
            }
        case "open-settings":
            if let tab = components.queryItems?.first(where: { $0.name == "tab" })?.value {
                UserDefaults.standard.set(tab, forKey: "selectedSettingsTab")
            }
            if let providerValue {
                UserDefaults.standard.set(providerValue, forKey: "selected_custom_usage_provider")
            }
            SettingsWindowController.shared.showSettingsWindow()
        default:
            break
        }
    }

    @MainActor
    private static func openCustomUsageSettings(providerID: String?) {
        UserDefaults.standard.set(SettingsTab.customUsage.rawValue, forKey: "selectedSettingsTab")
        if let providerID {
            UserDefaults.standard.set(providerID, forKey: "selected_custom_usage_provider")
        }
        SettingsWindowController.shared.showSettingsWindow()
    }

    /// Executes the appropriate tap action based on user settings
    @MainActor
    private static func performTapAction(
        openURL: () -> URL?,
        refresh: @escaping () async -> Void
    ) {
        switch WidgetTapActionStore.loadAction() {
        case .openWebsite:
            if let url = openURL() {
                NSWorkspace.shared.open(url)
            }
        case .refreshData:
            Task { await refresh() }
        }
    }
}

// MARK: - App Delegate

/// App delegate for handling deep links and configuring app as accessory (menu bar only)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    /// 起動完了時刻。起動直後の reopen 誤発火を無視するために使用する。
    private var launchedAt: Date?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // できるだけ早く accessory に設定し、Dock アイコンを表示しない。
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAt = Date()
        menuBarController = MenuBarController(appState: AppSharedState.shared)

        // 設定ウィンドウクローズ時にメニューバーアイコンの一時復活を終了する
        AppSharedState.shared.onSettingsWindowClosed = { [weak self] in
            self?.menuBarController?.endTemporaryRevealIfNeeded()
            AppSharedState.shared.applyBackgroundPolicyOnSettingsClose()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// 起動済みアプリを再度開いたときに呼ばれる。
    /// アイコン非表示中は一時復活させ、設定ウィンドウを開く。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 起動完了から 2 秒以内の reopen は LaunchServices 由来の可能性があるため無視する
        if let launchedAt, Date().timeIntervalSince(launchedAt) < 2.0 {
            return true
        }
        menuBarController?.temporarilyRevealForReopen()
        SettingsWindowController.shared.showSettingsWindow()
        return true
    }

    /// Handles incoming URLs from widget taps
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkHandler.handleURL(url)
        }
    }
}

// MARK: - Main App

/// Main SwiftUI App entry point. Menu bar and settings window are managed from AppKit controllers.
@main
struct AgentLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.migrateIdealToPacemakerKeys()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commandsRemoved()
    }

    private static func migrateIdealToPacemakerKeys() {
        guard let defaults = AppGroupDefaults.shared else { return }

        let oldWarningKey = "ideal_mode_warning_delta"
        let oldDangerKey = "ideal_mode_danger_delta"

        if let oldWarning = defaults.object(forKey: oldWarningKey) as? Double {
            if defaults.object(forKey: PacemakerThresholdKeys.warningDelta) == nil {
                defaults.set(oldWarning, forKey: PacemakerThresholdKeys.warningDelta)
            }
            defaults.removeObject(forKey: oldWarningKey)
        }

        if let oldDanger = defaults.object(forKey: oldDangerKey) as? Double {
            if defaults.object(forKey: PacemakerThresholdKeys.dangerDelta) == nil {
                defaults.set(oldDanger, forKey: PacemakerThresholdKeys.dangerDelta)
            }
            defaults.removeObject(forKey: oldDangerKey)
        }
    }
}
