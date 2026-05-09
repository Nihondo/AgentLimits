// MARK: - MenuBarController.swift
// NSStatusItem と NSMenu を管理するメニューバーコントローラー。
// AppDelegate から初期化・保持される。
// - NSStatusItem.button.image: SwiftUI ImageRenderer 出力を Combine で動的更新
// - NSMenu: ダッシュボード行を NSHostingView で描画、その他は通常の NSMenuItem

import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let appState: AppSharedState
    private var cancellables: Set<AnyCancellable> = []
    private var debounceTask: Task<Void, Never>?
    private static let debounceMs: UInt64 = 50

    // ダッシュボード行のホストビュー（再利用して rootView を更新）
    private var dashboardHostViews: [UsageProvider: NSHostingView<DashboardMenuItemView>] = [:]

    init(appState: AppSharedState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        buildMenu()
        observeChanges()
    }

    // MARK: - ボタン（メニューバーアイコン）

    private func configureButton() {
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.imagePosition = .imageOnly
        updateButtonImage()
    }

    private func updateButtonImage() {
        let snapshots = appState.viewModel.snapshots
        let displayMode = loadDisplayMode()

        // メニューバーボタンの実際のカラースキームを取得して ImageRenderer に渡す
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colorScheme: ColorScheme = isDarkMode ? .dark : .light

        let content = MenuBarLabelContentView(
            codexSnapshot: isMenuBarEnabled(.chatgptCodex) ? snapshots[.chatgptCodex] : nil,
            claudeSnapshot: isMenuBarEnabled(.claudeCode) ? snapshots[.claudeCode] : nil,
            copilotSnapshot: isMenuBarEnabled(.githubCopilot) ? snapshots[.githubCopilot] : nil,
            displayMode: displayMode
        )
        .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content.fixedSize())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let image = renderer.nsImage {
            image.isTemplate = false
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = NSImage(resource: .menuBarIcon)
        }
    }

    private func isMenuBarEnabled(_ provider: UsageProvider) -> Bool {
        let defaults = UserDefaults.standard
        switch provider {
        case .chatgptCodex: return defaults.bool(forKey: UserDefaultsKeys.menuBarStatusCodexEnabled)
        case .claudeCode: return defaults.bool(forKey: UserDefaultsKeys.menuBarStatusClaudeEnabled)
        case .githubCopilot: return defaults.bool(forKey: UserDefaultsKeys.menuBarStatusCopilotEnabled)
        }
    }

    private func loadDisplayMode() -> UsageDisplayMode {
        UsageDisplayMode.makeSelectableMode(
            from: UserDefaults.standard.string(forKey: UserDefaultsKeys.displayMode)
        )
    }

    // MARK: - メニュー構築

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // MARK: - Combine 監視

    private func observeChanges() {
        appState.viewModel.objectWillChange
            .sink { [weak self] _ in self?.scheduleImageUpdate() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.scheduleImageUpdate() }
            .store(in: &cancellables)
    }

    private func scheduleImageUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceMs * 1_000_000)
            guard !Task.isCancelled else { return }
            updateButtonImage()
        }
    }
}

// MARK: - NSMenuDelegate

extension MenuBarController: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        // NSMenuDelegate はメインスレッドから呼ばれるため assumeIsolated で同期実行
        MainActor.assumeIsolated {
            self.rebuildMenu(menu)
        }
    }

    @MainActor
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // ダッシュボード行
        let displayMode = loadDisplayMode()
        let snapshots = appState.viewModel.snapshots
        let visibleProviders = UsageProvider.allCases.filter {
            isDashboardEnabled($0) && snapshots[$0] != nil
        }
        for (index, provider) in visibleProviders.enumerated() {
            guard let snapshot = snapshots[provider] else { continue }
            let item = makeDashboardItem(provider: provider, snapshot: snapshot, displayMode: displayMode)
            menu.addItem(item)
            // プロバイダー間にセパレーター（最後は除く）
            if index < visibleProviders.count - 1 {
                menu.addItem(.separator())
            }
        }
        if !visibleProviders.isEmpty {
            menu.addItem(.separator())
        }

        // 設定を開く
        menu.addItem(makeActionItem(
            title: "menu.openSettings".localized(),
            image: NSImage(systemSymbolName: "gear", accessibilityDescription: nil),
            action: #selector(openSettings)
        ))
        menu.addItem(.separator())

        // 表示モードサブメニュー
        menu.addItem(makeDisplayModeItem())
        // 言語サブメニュー
        menu.addItem(makeLanguageItem())
        // Wake up サブメニュー
        menu.addItem(makeWakeUpItem())
        menu.addItem(.separator())

        // ログイン時に起動
        let loginItem = makeActionItem(
            title: "wakeUp.startAtLogin".localized(),
            image: nil,
            action: #selector(toggleLoginItem)
        )
        loginItem.state = LoginItemManager.shared.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        // アップデート確認
        let updateItem = makeActionItem(
            title: "menu.checkForUpdates".localized(),
            image: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil),
            action: #selector(checkForUpdates)
        )
        updateItem.isEnabled = AppUpdateController.shared.canCheckForUpdates
        menu.addItem(updateItem)
        menu.addItem(.separator())

        // About
        menu.addItem(makeActionItem(
            title: "menu.about".localized(),
            image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil),
            action: #selector(showAbout)
        ))
        menu.addItem(.separator())

        // 終了
        menu.addItem(makeActionItem(
            title: "menu.quit".localized(),
            image: NSImage(systemSymbolName: "power", accessibilityDescription: nil),
            action: #selector(quit)
        ))
    }

    // MARK: - ダッシュボード行

    private func makeDashboardItem(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        displayMode: UsageDisplayMode
    ) -> NSMenuItem {
        let view = DashboardMenuItemView(
            provider: provider,
            snapshot: snapshot,
            displayMode: displayMode
        )
        let hosting = NSHostingView(rootView: view)
        // fittingSize で自然な高さを取得しつつ、幅は最小 300px を確保してメニューが狭くならないようにする
        let fittingSize = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: max(300, fittingSize.width), height: fittingSize.height)
        hosting.autoresizingMask = [.width]

        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = true
        return item
    }

    // MARK: - ヘルパー

    private func makeActionItem(title: String, image: NSImage?, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image
        item.isEnabled = true
        return item
    }

    private func isDashboardEnabled(_ provider: UsageProvider) -> Bool {
        let defaults = UserDefaults.standard
        switch provider {
        case .chatgptCodex:
            return defaults.object(forKey: UserDefaultsKeys.menuBarDashboardCodexEnabled) as? Bool ?? true
        case .claudeCode:
            return defaults.object(forKey: UserDefaultsKeys.menuBarDashboardClaudeEnabled) as? Bool ?? true
        case .githubCopilot:
            return defaults.object(forKey: UserDefaultsKeys.menuBarDashboardCopilotEnabled) as? Bool ?? true
        }
    }

    // MARK: - サブメニュー: 表示モード

    private func makeDisplayModeItem() -> NSMenuItem {
        let current = loadDisplayMode()
        let sub = NSMenu()
        for mode in UsageDisplayMode.selectableCases {
            let item = NSMenuItem(
                title: mode.localizedDisplayName,
                action: #selector(setDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.state = current == mode ? .on : .off
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: "menu.displayMode".localized(), action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        parent.submenu = sub
        return parent
    }

    // MARK: - サブメニュー: 言語

    private func makeLanguageItem() -> NSMenuItem {
        let languages = LanguageManager.shared.availableLanguages
        let current = LanguageManager.shared.currentLanguage
        let sub = NSMenu()
        for language in languages {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(setLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language
            item.state = current == language ? .on : .off
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: "menu.language".localized(), action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        parent.submenu = sub
        return parent
    }


    // MARK: - サブメニュー: Wake up

    private func makeWakeUpItem() -> NSMenuItem {
        let sub = NSMenu()
        for provider in WakeUpScheduler.supportedProviders {
            let title = "\(provider.displayName) " + "menu.wakeUpNow".localized()
            let item = NSMenuItem(title: title, action: #selector(triggerWakeUp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: "menu.wakeUp".localized(), action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "alarm", accessibilityDescription: nil)
        parent.submenu = sub
        return parent
    }

    // MARK: - Actions

    @objc private func openSettings() {
        AppSharedState.shared.openSettingsAction?()
    }

    @objc private func toggleLoginItem() {
        LoginItemManager.shared.setEnabled(!LoginItemManager.shared.isEnabled)
    }

    @objc private func checkForUpdates() {
        AppUpdateController.shared.checkForUpdates()
    }

    @objc private func showAbout() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .credits: makeAboutCredits()
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeAboutCredits() -> NSAttributedString {
        let copyright = resolveAboutCopyright()
        let repositoryURLString = "https://products.desireforwealth.com/products/agentlimits"
        let creditsText = "\(copyright)\nWebsite: \(repositoryURLString)"
        let attributed = NSMutableAttributedString(string: creditsText)
        let linkRange = (creditsText as NSString).range(of: repositoryURLString)
        attributed.addAttribute(.link, value: repositoryURLString, range: linkRange)
        return attributed
    }

    private func resolveAboutCopyright() -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return "Copyright © 2025-2026 Nihondo"
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? UsageDisplayMode else { return }
        let displayMode = mode.normalizedSelectableMode
        UserDefaults.standard.set(displayMode.rawValue, forKey: UserDefaultsKeys.displayMode)
        appState.viewModel.updateDisplayMode(displayMode)
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? AppLanguageOption else { return }
        LanguageManager.shared.setLanguage(language)
    }

    @objc private func triggerWakeUp(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? UsageProvider else { return }
        Task { await WakeUpScheduler.shared.triggerWakeUp(for: provider) }
    }
}
