// MARK: - MenuBarController.swift
// NSStatusItem と NSMenu を管理するメニューバーコントローラー。
// AppDelegate から初期化・保持される。
// - NSStatusItem.button.image: SwiftUI ImageRenderer 出力を Combine で動的更新
// - NSMenu: ダッシュボード行を NSHostingView で描画、その他は通常の NSMenuItem

import AppKit
import Combine
import SwiftUI

// MARK: - MenuBarIconCacheKey

/// メニューバーアイコンの描画入力を表すキャッシュキー。
/// 前回と同一であれば ImageRenderer の実行をスキップする。
private struct MenuBarIconCacheKey: Equatable {
    struct ServiceEntry: Equatable {
        let serviceKey: UsageServiceKey
        let fetchedAt: Date?
        let isEnabled: Bool
    }
    let services: [ServiceEntry]
    let displayMode: UsageDisplayMode
    let colorScheme: ColorScheme
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let appState: AppSharedState
    private var cancellables: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?
    private var debounceTask: Task<Void, Never>?
    private static let debounceMs: UInt64 = 300
    private var lastIconCacheKey: MenuBarIconCacheKey?
    // addObserver と removeObserver で同じインスタンスを使うために保持する
    // nonisolated(unsafe): deinit（nonisolated）からアクセスするため
    nonisolated(unsafe) private var observedAppGroupDefaults: UserDefaults?

    // ダッシュボード行のホストビュー（再利用して rootView を更新）
    private var dashboardHostViews: [UsageProvider: NSHostingView<DashboardMenuItemView>] = [:]

    /// 再起動（reopen）で一時的にアイコンを復活させている状態
    private var isTemporarilyRevealed = false

    init(appState: AppSharedState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        buildMenu()
        observeChanges()
        applyIconVisibility()
    }

    // MARK: - アイコン表示/非表示制御

    /// UserDefaults の `menu_bar_icon_hidden` と一時復活フラグに基づきアイコン表示を制御する
    private func applyIconVisibility() {
        let isHidden = UserDefaults.standard.bool(forKey: UserDefaultsKeys.menuBarIconHidden)
        statusItem.isVisible = !(isHidden && !isTemporarilyRevealed)
    }

    /// 再起動（reopen）時にアイコンを一時復活させる。非表示設定時のみフラグを立てる。
    func temporarilyRevealForReopen() {
        let isHidden = UserDefaults.standard.bool(forKey: UserDefaultsKeys.menuBarIconHidden)
        guard isHidden else { return }
        isTemporarilyRevealed = true
        applyIconVisibility()
    }

    /// 設定ウィンドウクローズ時に一時復活を終了し、設定に応じてアイコンを再非表示にする
    func endTemporaryRevealIfNeeded() {
        guard isTemporarilyRevealed else { return }
        isTemporarilyRevealed = false
        applyIconVisibility()
    }

    // MARK: - ボタン（メニューバーアイコン）

    private func configureButton() {
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.imagePosition = .imageOnly
        updateButtonImage()
    }

    private func updateButtonImage() {
        let snapshots = allPresentationSnapshots
        let displayMode = loadDisplayMode()
        let colorScheme = resolveButtonColorScheme()
        let orderedServices = ProviderOrderStore.loadServiceOrder()

        // 前回の描画入力と同一であれば ImageRenderer をスキップする
        let cacheKey = MenuBarIconCacheKey(
            services: orderedServices.map { serviceKey in
                MenuBarIconCacheKey.ServiceEntry(
                    serviceKey: serviceKey,
                    fetchedAt: isMenuBarEnabled(serviceKey) ? snapshots[serviceKey]?.fetchedAt : nil,
                    isEnabled: isMenuBarEnabled(serviceKey)
                )
            },
            displayMode: displayMode,
            colorScheme: colorScheme
        )
        guard cacheKey != lastIconCacheKey else { return }
        lastIconCacheKey = cacheKey

        // メニューバーボタン自身の見た目を基準に ImageRenderer の色を決める。
        let orderedSnapshots = orderedServices.map { serviceKey in
            (serviceKey: serviceKey, snapshot: isMenuBarEnabled(serviceKey) ? snapshots[serviceKey] : nil)
        }
        let content = CommonUsageMenuBarLabelView(
            orderedSnapshots: orderedSnapshots,
            displayMode: displayMode,
            colorScheme: colorScheme
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

    private func isMenuBarEnabled(_ serviceKey: UsageServiceKey) -> Bool {
        if let provider = serviceKey.builtInProvider {
            return isMenuBarEnabled(provider)
        }
        guard let providerID = serviceKey.customProviderID else { return false }
        return appState.customUsageViewModel.serviceStore
            .service(providerID: providerID)?.isMenuBarEnabled == true
    }

    private var allPresentationSnapshots: [UsageServiceKey: UsagePresentationSnapshot] {
        var result = Dictionary(uniqueKeysWithValues: appState.viewModel.snapshots.values.map { snapshot in
            let presentation = UsagePresentationSnapshot(builtIn: snapshot)
            return (presentation.serviceKey, presentation)
        })
        result.merge(appState.customUsageViewModel.presentationSnapshots) { _, custom in custom }
        return result
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

    // MARK: - 変更監視

    private func observeChanges() {
        appState.viewModel.objectWillChange
            .sink { [weak self] _ in self?.scheduleImageUpdate() }
            .store(in: &cancellables)

        appState.customUsageViewModel.objectWillChange
            .sink { [weak self] _ in self?.scheduleImageUpdate() }
            .store(in: &cancellables)

        // UserDefaults.didChangeNotification（全変更）の代わりに
        // アイコン表示に関係するキーのみを KVO で監視する
        for key in [
            UserDefaultsKeys.displayMode,
            UserDefaultsKeys.menuBarStatusCodexEnabled,
            UserDefaultsKeys.menuBarStatusClaudeEnabled,
            UserDefaultsKeys.menuBarStatusCopilotEnabled,
            UserDefaultsKeys.providerDisplayOrder,
            UserDefaultsKeys.menuBarIconHidden,
        ] {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
        // addObserver と removeObserver で同じインスタンスを保持する
        let appGroupDefaults = AppGroupDefaults.shared
        observedAppGroupDefaults = appGroupDefaults
        for key in [
            SharedUserDefaultsKeys.menuBarShowPacemakerValue,
            UsageColorKeys.statusGreen,
            UsageColorKeys.statusOrange,
            UsageColorKeys.statusRed,
            UsageColorKeys.pacemakerStatusOrange,
            UsageColorKeys.pacemakerStatusRed,
            PacemakerThresholdKeys.warningDelta,
            PacemakerThresholdKeys.dangerDelta,
            UsageStatusThresholdStore.revisionKey,
        ] {
            appGroupDefaults?.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.scheduleImageUpdate() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.scheduleImageUpdate() }
            .store(in: &cancellables)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .sink { [weak self] _ in self?.scheduleImageUpdate() }
            .store(in: &cancellables)

        appearanceObservation = statusItem.button?.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.scheduleImageUpdate()
            }
        }
    }

    // KVO コールバック（特定キーの変更時のみ呼ばれる）
    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        // インライン定義: nonisolated コンテキストから @MainActor な型メンバーを参照できないため
        let iconVisibilityKey = "menu_bar_icon_hidden"
        let imageObservedKeys = [
            "usage_display_mode", "menu_bar_status_codex_enabled",
            "menu_bar_status_claude_enabled", "menu_bar_status_copilot_enabled",
            "provider_display_order", "menu_bar_show_pacemaker_value",
            "usage_color_green", "usage_color_orange", "usage_color_red",
            "usage_color_pacemaker_status_orange", "usage_color_pacemaker_status_red",
            "pacemaker_warning_delta", "pacemaker_danger_delta",
            "usage_color_threshold_revision",
        ]
        guard let keyPath else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        if keyPath == iconVisibilityKey {
            // アイコン非表示トグルの即時反映
            Task { @MainActor [weak self] in
                self?.applyIconVisibility()
            }
            return
        }
        guard imageObservedKeys.contains(keyPath) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        // 設定変更はキャッシュを無効化して強制再描画する
        Task { @MainActor [weak self] in
            self?.lastIconCacheKey = nil
            self?.scheduleImageUpdate()
        }
    }

    deinit {
        let standardKeys = [
            "usage_display_mode", "menu_bar_status_codex_enabled",
            "menu_bar_status_claude_enabled", "menu_bar_status_copilot_enabled",
            "provider_display_order", "menu_bar_icon_hidden",
        ]
        for key in standardKeys {
            UserDefaults.standard.removeObserver(self, forKeyPath: key)
        }
        // addObserver と同じインスタンスで解除する
        let appGroupKeys = [
            "menu_bar_show_pacemaker_value",
            "usage_color_green", "usage_color_orange", "usage_color_red",
            "usage_color_pacemaker_status_orange", "usage_color_pacemaker_status_red",
            "pacemaker_warning_delta", "pacemaker_danger_delta",
            "usage_color_threshold_revision",
        ]
        for key in appGroupKeys {
            observedAppGroupDefaults?.removeObserver(self, forKeyPath: key)
        }
    }

    private func scheduleImageUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceMs * 1_000_000)
            guard !Task.isCancelled else { return }
            updateButtonImage()
        }
    }

    private func resolveButtonColorScheme() -> ColorScheme {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let matched = appearance.bestMatch(from: [
            .darkAqua,
            .aqua,
            .vibrantDark,
            .vibrantLight,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastAqua
        ])
        switch matched {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua:
            return .dark
        default:
            return .light
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
        let builtInSnapshots = appState.viewModel.snapshots
        let presentationSnapshots = allPresentationSnapshots
        let visibleServices = ProviderOrderStore.loadServiceOrder().filter {
            isDashboardEnabled($0) && presentationSnapshots[$0] != nil
        }
        for (index, serviceKey) in visibleServices.enumerated() {
            let item: NSMenuItem
            if let provider = serviceKey.builtInProvider,
               let snapshot = builtInSnapshots[provider] {
                item = makeDashboardItem(provider: provider, snapshot: snapshot, displayMode: displayMode)
            } else if let providerID = serviceKey.customProviderID,
                      let snapshot = presentationSnapshots[serviceKey],
                      let service = appState.customUsageViewModel.serviceStore.service(providerID: providerID) {
                item = makeCustomDashboardItem(
                    snapshot: snapshot,
                    service: service,
                    displayMode: displayMode
                )
            } else {
                continue
            }
            menu.addItem(item)
            // プロバイダー間にセパレーター（最後は除く）
            if index < visibleServices.count - 1 {
                menu.addItem(.separator())
            }
        }
        if !visibleServices.isEmpty {
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
            image: NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil),
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
        // NSMenu の NSVisualEffectView 背景との合成を正確にするため透明に設定
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        // fittingSize で自然な高さを取得しつつ、幅は最小 300px を確保してメニューが狭くならないようにする
        let fittingSize = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: max(300, fittingSize.width), height: fittingSize.height)
        hosting.autoresizingMask = [.width]

        let item = NSMenuItem()
        item.view = hosting
        item.isEnabled = true
        return item
    }

    private func makeCustomDashboardItem(
        snapshot: UsagePresentationSnapshot,
        service: CustomUsageService,
        displayMode: UsageDisplayMode
    ) -> NSMenuItem {
        let status = appState.customUsageViewModel.serviceStore.runStatuses[service.providerID]
        let view = CustomUsageDashboardMenuItemView(
            snapshot: snapshot,
            displayMode: displayMode,
            websiteURL: service.websiteURL,
            lastError: status?.lastError
        )
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        let fittingSize = hosting.fittingSize
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: max(300, fittingSize.width),
            height: fittingSize.height
        )
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

    private func isDashboardEnabled(_ serviceKey: UsageServiceKey) -> Bool {
        if let provider = serviceKey.builtInProvider {
            return isDashboardEnabled(provider)
        }
        guard let providerID = serviceKey.customProviderID else { return false }
        return appState.customUsageViewModel.serviceStore
            .service(providerID: providerID)?.isDashboardEnabled == true
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
        SettingsWindowController.shared.showSettingsWindow()
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
