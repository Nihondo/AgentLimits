// MARK: - SettingsWindowController.swift
// AppKit-managed settings window for the menu bar app.
// Creates the SwiftUI settings view only when the user opens settings.

import AppKit
import SwiftUI

/// 設定画面を必要時にだけ生成・表示する AppKit コントローラー。
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("settings")
    private let appState = AppSharedState.shared

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 設定ウィンドウを表示し、既に存在する場合は前面へ移動する。
    func showSettingsWindow() {
        prepareSettingsState()

        if window == nil {
            window = makeSettingsWindow()
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func prepareSettingsState() {
        appState.viewModel.updateDisplayMode(
            UsageDisplayMode.makeSelectableMode(
                from: UserDefaults.standard.string(forKey: UserDefaultsKeys.displayMode)
            )
        )
        appState.startBackgroundRefresh()
        LoginItemManager.shared.updateStatus()
        _ = AppUpdateController.shared
    }

    private func makeSettingsWindow() -> NSWindow {
        let rootView = SettingsTabView(
            viewModel: appState.viewModel,
            webViewPool: appState.webViewPool,
            tokenUsageViewModel: appState.tokenUsageViewModel
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "window.settings.title".localized()
        window.identifier = Self.settingsWindowIdentifier
        window.styleMask = [.titled, .closable, .resizable]
        window.minSize = NSSize(
            width: DesignTokens.WindowSize.minWidth,
            height: DesignTokens.WindowSize.minHeight
        )
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        return window
    }
}
