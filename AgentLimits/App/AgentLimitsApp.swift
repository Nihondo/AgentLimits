// MARK: - AgentLimitsApp.swift
// Main application entry point for AgentLimits menu bar app.
// Provides menu bar UI, settings window, and deep link handling.

import SwiftUI
import AppKit
import Combine

// MARK: - Window Configuration

private enum WindowId {
    static let settings = "settings"
}

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
        case "open-settings":
            AppSharedState.shared.openSettingsAction?()
        default:
            break
        }
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

    func applicationWillFinishLaunching(_ notification: Notification) {
        // できるだけ早く accessory に設定し、SwiftUI が起動時にウィンドウを表示しないようにする
        NSApp.setActivationPolicy(.accessory)
        // ウィンドウ状態の復元を無効化（前回終了時に開いていたウィンドウを復元しない）
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(appState: AppSharedState.shared)
        // SwiftUI Window シーンが applicationDidFinishLaunching 後に非同期でウィンドウを
        // 作成・表示する場合があるため、次のランループで改めて非表示にする
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.orderOut(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Handles incoming URLs from widget taps
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkHandler.handleURL(url)
        }
    }
}

// MARK: - Main App

/// Main SwiftUI App providing settings window (menu bar は AppDelegate 側の MenuBarController が管理)
@main
struct AgentLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private var appState: AppSharedState { AppSharedState.shared }

    init() {
        Self.migrateIdealToPacemakerKeys()
    }

    var body: some Scene {
        Window("AgentLimits", id: WindowId.settings) {
            SettingsTabView(
                viewModel: appState.viewModel,
                webViewPool: appState.webViewPool,
                tokenUsageViewModel: appState.tokenUsageViewModel
            )
            .onAppear {
                // MenuBarController（AppKit）から設定ウィンドウを開けるようにコールバックを注入
                appState.openSettingsAction = {
                    openWindow(id: WindowId.settings)
                    NSApp.activate(ignoringOtherApps: true)
                }
                appState.viewModel.updateDisplayMode(
                    UsageDisplayMode.makeSelectableMode(
                        from: UserDefaults.standard.string(forKey: UserDefaultsKeys.displayMode)
                    )
                )
                appState.startBackgroundRefresh()
                LoginItemManager.shared.updateStatus()
                _ = AppUpdateController.shared
            }
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
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
