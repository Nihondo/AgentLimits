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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }

    /// Handles incoming URLs from widget taps
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkHandler.handleURL(url)
        }
    }
}

// MARK: - Main App

/// Main SwiftUI App providing menu bar extra and settings window
@main
struct AgentLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var appState: AppSharedState { AppSharedState.shared }

    init() {
        Self.migrateIdealToPacemakerKeys()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
        }
        Window("AgentLimits", id: WindowId.settings) {
            SettingsTabView(
                viewModel: appState.viewModel,
                webViewPool: appState.webViewPool,
                tokenUsageViewModel: appState.tokenUsageViewModel
            )
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

// MARK: - Menu Bar Label

/// Dynamic menu bar label showing usage status for enabled providers.
/// Uses debouncing to avoid excessive ImageRenderer calls when multiple properties change rapidly.
private struct MenuBarLabelView: View {
    @EnvironmentObject private var appState: AppSharedState
    @AppStorage(UserDefaultsKeys.menuBarStatusCodexEnabled) private var codexEnabled = false
    @AppStorage(UserDefaultsKeys.menuBarStatusClaudeEnabled) private var claudeEnabled = false
    @AppStorage(UserDefaultsKeys.menuBarStatusCopilotEnabled) private var copilotEnabled = false
    @AppStorage(UserDefaultsKeys.displayMode) private var displayMode: UsageDisplayMode = .used
    @AppStorage(UserDefaultsKeys.menuBarShowPacemakerValue, store: AppGroupDefaults.shared)
    private var showPacemakerValue = true
    @AppStorage(UsageStatusThresholdStore.revisionKey, store: AppGroupDefaults.shared)
    private var thresholdRevision: Double = 0
    @AppStorage(UsageColorKeys.statusGreen, store: AppGroupDefaults.shared)
    private var statusGreenHex: String = ""
    @AppStorage(UsageColorKeys.statusOrange, store: AppGroupDefaults.shared)
    private var statusOrangeHex: String = ""
    @AppStorage(UsageColorKeys.statusRed, store: AppGroupDefaults.shared)
    private var statusRedHex: String = ""
    @AppStorage(UsageColorKeys.pacemakerStatusOrange, store: AppGroupDefaults.shared)
    private var pacemakerStatusOrangeHex: String = ""
    @AppStorage(UsageColorKeys.pacemakerStatusRed, store: AppGroupDefaults.shared)
    private var pacemakerStatusRedHex: String = ""
    @State private var renderedImage: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    /// Task for debouncing image updates
    @State private var debounceTask: Task<Void, Never>?

    /// Debounce interval for batching rapid updates (in milliseconds)
    private static let debounceIntervalMs: UInt64 = 50

    var body: some View {
        Group {
            if let renderedImage {
                Image(nsImage: renderedImage)
                    .renderingMode(.original)
            } else {
                Image(.menuBarIcon)
            }
        }
        .onAppear {
            // Initial render without debounce
            updateRenderedImage()
        }
        .onChange(of: codexEnabled) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: claudeEnabled) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: copilotEnabled) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: displayMode) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: showPacemakerValue) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: colorScheme) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: thresholdRevision) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: statusGreenHex) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: statusOrangeHex) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: statusRedHex) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: pacemakerStatusOrangeHex) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: pacemakerStatusRedHex) { _, _ in
            scheduleImageUpdate()
        }
        .onReceive(appState.viewModel.objectWillChange) { _ in
            scheduleImageUpdate()
        }
    }

    // MARK: - Debounced Update

    /// Schedules an image update with debouncing.
    /// Cancels any pending update and schedules a new one after the debounce interval.
    /// This prevents excessive ImageRenderer calls when multiple properties change rapidly.
    private func scheduleImageUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceIntervalMs * 1_000_000)
            guard !Task.isCancelled else { return }
            updateRenderedImage()
        }
    }

    // MARK: - Image Rendering

    /// Renders the menu bar label content to an NSImage.
    /// Uses ImageRenderer to generate a bitmap from the SwiftUI view.
    private func updateRenderedImage() {
        let codexSnapshot = codexEnabled ? appState.viewModel.snapshots[.chatgptCodex] : nil
        let claudeSnapshot = claudeEnabled ? appState.viewModel.snapshots[.claudeCode] : nil
        let copilotSnapshot = copilotEnabled ? appState.viewModel.snapshots[.githubCopilot] : nil
        let content = MenuBarLabelContentView(
            codexSnapshot: codexSnapshot,
            claudeSnapshot: claudeSnapshot,
            copilotSnapshot: copilotSnapshot,
            displayMode: displayMode
        )
        .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content.fixedSize())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else {
            renderedImage = nil
            return
        }
        image.isTemplate = false
        renderedImage = image
    }
}

private struct MenuBarLabelContentView: View {
    let codexSnapshot: UsageSnapshot?
    let claudeSnapshot: UsageSnapshot?
    let copilotSnapshot: UsageSnapshot?
    let displayMode: UsageDisplayMode

    var body: some View {
        HStack(spacing: 6) {
            Image(.menuBarIcon)
            if let codexSnapshot {
                MenuBarProviderStatusView(
                    provider: .chatgptCodex,
                    primaryWindow: codexSnapshot.primaryWindow,
                    secondaryWindow: codexSnapshot.secondaryWindow,
                    displayMode: displayMode
                )
            }
            if let claudeSnapshot {
                MenuBarProviderStatusView(
                    provider: .claudeCode,
                    primaryWindow: claudeSnapshot.primaryWindow,
                    secondaryWindow: claudeSnapshot.secondaryWindow,
                    displayMode: displayMode
                )
            }
            if let copilotSnapshot {
                MenuBarProviderStatusView(
                    provider: .githubCopilot,
                    primaryWindow: copilotSnapshot.primaryWindow,
                    secondaryWindow: copilotSnapshot.secondaryWindow,
                    displayMode: displayMode
                )
            }
        }
    }
}

/// Status view for a single provider showing 5h/1w usage in two rows
private struct MenuBarProviderStatusView: View {
    let provider: UsageProvider
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
    let displayMode: UsageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(provider.displayName)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.primary)
            MenuBarPercentLineView(
                provider: provider,
                primaryWindow: primaryWindow,
                secondaryWindow: secondaryWindow,
                displayMode: displayMode
            )
        }
    }
}

/// A compact menu bar line showing primary/secondary usage percentages
private struct MenuBarPercentLineView: View {
    let provider: UsageProvider
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
    let displayMode: UsageDisplayMode
    @AppStorage(UserDefaultsKeys.menuBarShowPacemakerValue, store: AppGroupDefaults.shared)
    private var showPacemakerValue: Bool = true
    @AppStorage(UsageColorKeys.statusGreen, store: AppGroupDefaults.shared)
    private var statusGreenHex: String = ""
    @AppStorage(UsageColorKeys.statusOrange, store: AppGroupDefaults.shared)
    private var statusOrangeHex: String = ""
    @AppStorage(UsageColorKeys.statusRed, store: AppGroupDefaults.shared)
    private var statusRedHex: String = ""

    var body: some View {
        HStack(spacing: 2) {
            percentTextView(primaryWindow, windowKind: .primary)
            if provider != .githubCopilot {
                Text("/")
                    .foregroundStyle(.secondary)
                percentTextView(secondaryWindow, windowKind: .secondary)
            }
        }
        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func percentTextView(_ window: UsageWindow?, windowKind: UsageWindowKind) -> some View {
        if let window {
            let statusColor = resolveStatusColor(window, windowKind: windowKind)
            let percent = displayMode.displayPercent(from: window.usedPercent, window: window)
            let displayText = UsagePercentFormatter.formatPercentText(percent)
            if showPacemakerValue,
               let pacemakerPercent = window.calculatePacemakerPercent() {
                // ステータスレベルを取得して矢印アイコンを決定
                let level = UsageStatusLevelResolver.levelForPacemakerMode(
                    usedPercent: window.usedPercent,
                    pacemakerPercent: pacemakerPercent,
                    warningDelta: PacemakerThresholdSettings.loadWarningDelta(),
                    dangerDelta: PacemakerThresholdSettings.loadDangerDelta()
                )
                let arrowIcon = level.pacemakerArrowIcon
                let indicatorColor = level.pacemakerIndicatorColor
                // "45%↑" 形式で表示（超過時のみ）
                if arrowIcon.isEmpty {
                    Text(displayText)
                        .foregroundColor(statusColor)
                } else {
                    Text(displayText)
                        .foregroundColor(statusColor) +
                    Text(arrowIcon)
                        .foregroundColor(indicatorColor)
                }
            } else {
                Text(displayText)
                    .foregroundColor(statusColor)
            }
        } else {
            Text(UsagePercentFormatter.formatPercentText(nil))
                .foregroundStyle(.secondary)
        }
    }

    private func resolveStatusColor(_ window: UsageWindow?, windowKind: UsageWindowKind) -> Color {
        guard let window else { return .secondary }
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: provider, windowKind: windowKind)
        let level = UsageStatusLevelResolver.level(
            for: window.usedPercent,
            isRemainingMode: false,
            warningThreshold: thresholds.warningPercent,
            dangerThreshold: thresholds.dangerPercent
        )
        switch level {
        case .green:
            return resolveStoredColor(from: statusGreenHex, defaultColor: .green)
        case .orange:
            return resolveStoredColor(from: statusOrangeHex, defaultColor: .orange)
        case .red:
            return resolveStoredColor(from: statusRedHex, defaultColor: .red)
        }
    }

    private func resolveStoredColor(from storedValue: String, defaultColor: Color) -> Color {
        let trimmedValue = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedValue = trimmedValue.isEmpty ? nil : trimmedValue
        return ColorHexCodec.resolveColor(from: resolvedValue, defaultColor: defaultColor)
    }
}

// MARK: - Menu Bar Content

/// A label that shows a checkmark when selected
private struct CheckmarkLabel: View {
    let title: String
    let isSelected: Bool

    init(_ title: String, isSelected: Bool) {
        self.title = title
        self.isSelected = isSelected
    }

    var body: some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// ダッシュボード行: 1プロバイダーの5h残り時間と週次リセット時刻を1行で表示
/// macOS メニューの Button ラベルは VStack 複数行を描画できないため単一 Label を使用する
private struct MenuBarDashboardRowView: View {
    let provider: UsageProvider
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?

    var body: some View {
        Button {
            NSWorkspace.shared.open(provider.usageURL)
        } label: {
            Label(summaryText, systemImage: "chart.bar.fill")
                .font(.system(.body, design: .monospaced))
        }
    }

    private var summaryText: String {
        if provider == .githubCopilot {
            return "\(provider.displayName)  \(copilotResetText)"
        }
        return "\(provider.displayName)  \(remainingText)  \(weeklyResetText)"
    }

    // MARK: - Codex / Claude Code

    private var remainingText: String {
        guard let window = primaryWindow else { return "--" }
        let remainingSeconds = max(0, window.limitWindowSeconds * (1.0 - window.usedPercent / 100.0))
        let timeString: String
        if remainingSeconds >= 3600 {
            timeString = String(format: "menu.dashboard.remainingHours".localized(), remainingSeconds / 3600.0)
        } else {
            timeString = String(format: "menu.dashboard.remainingMinutes".localized(), max(1, Int(remainingSeconds) / 60))
        }
        return String(format: "menu.dashboard.remaining5h".localized(), timeString)
    }

    private var weeklyResetText: String {
        guard let window = secondaryWindow, let resetAt = window.resetAt else { return "--" }
        return String(format: "menu.dashboard.weeklyReset".localized(), formatResetRelative(resetAt))
    }

    // MARK: - Copilot (月次)

    private var copilotResetText: String {
        guard let window = primaryWindow, let resetAt = window.resetAt else { return "--" }
        return String(format: "menu.dashboard.weeklyReset".localized(), formatResetRelative(resetAt))
    }

    // MARK: - 共通

    private func formatResetRelative(_ resetAt: Date) -> String {
        let remaining = resetAt.timeIntervalSinceNow
        if remaining <= 60 {
            return "menu.dashboard.soon".localized()
        } else if remaining >= 86400 {
            return String(format: "menu.dashboard.resetDaysLater".localized(), remaining / 86400.0)
        } else if remaining >= 3600 {
            return String(format: "menu.dashboard.resetHoursLater".localized(), remaining / 3600.0)
        } else {
            return String(format: "menu.dashboard.resetMinutesLater".localized(), max(1, Int(remaining) / 60))
        }
    }
}

/// Menu bar dropdown content with settings, display mode, and language options
private struct MenuBarContentView: View {
    @AppStorage(UserDefaultsKeys.displayMode) private var displayMode: UsageDisplayMode = .used
    @AppStorage(UserDefaultsKeys.menuBarDashboardCodexEnabled) private var dashboardCodexEnabled = true
    @AppStorage(UserDefaultsKeys.menuBarDashboardClaudeEnabled) private var dashboardClaudeEnabled = true
    @AppStorage(UserDefaultsKeys.menuBarDashboardCopilotEnabled) private var dashboardCopilotEnabled = true
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppSharedState
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var loginItemManager = LoginItemManager.shared

    var body: some View {
        dashboardSection
        Button {
            openWindow(id: WindowId.settings)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("menu.openSettings".localized(), systemImage: "gear")
        }
        Divider()
        displayModeMenu
        languageMenu
        wakeUpMenu
        Divider()
        loginAtStartupButton
        Divider()
        Button {
            AppUpdateController.shared.checkForUpdates()
        } label: {
            Label("menu.checkForUpdates".localized(), systemImage: "arrow.down.circle")
        }
        .disabled(!AppUpdateController.shared.canCheckForUpdates)
        Divider()
        Button {
            presentAboutPanel()
        } label: {
            Label("menu.about".localized(), systemImage: "info.circle")
        }
        Divider()
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("menu.quit".localized(), systemImage: "power")
        }
        .onChange(of: displayMode) {
            appState.viewModel.updateDisplayMode(displayMode)
        }
        .onAppear {
            appState.viewModel.updateDisplayMode(displayMode)
            appState.startBackgroundRefresh()
            loginItemManager.updateStatus()
            _ = AppUpdateController.shared
        }
    }

    // MARK: - Menu Sections

    @ViewBuilder
    private var dashboardSection: some View {
        let snapshots = appState.viewModel.snapshots
        let dashboardFlags: [UsageProvider: Bool] = [
            .chatgptCodex: dashboardCodexEnabled,
            .claudeCode: dashboardClaudeEnabled,
            .githubCopilot: dashboardCopilotEnabled
        ]
        let visibleProviders = UsageProvider.allCases.filter {
            dashboardFlags[$0] == true && snapshots[$0] != nil
        }
        if !visibleProviders.isEmpty {
            ForEach(visibleProviders) { provider in
                if let snapshot = snapshots[provider] {
                    MenuBarDashboardRowView(
                        provider: provider,
                        primaryWindow: snapshot.primaryWindow,
                        secondaryWindow: snapshot.secondaryWindow
                    )
                }
            }
            Divider()
        }
    }

    private var displayModeMenu: some View {
        Menu {
            Button { displayMode = .used } label: {
                CheckmarkLabel("menu.displayMode.used".localized(), isSelected: displayMode == .used)
            }
            Button { displayMode = .remaining } label: {
                CheckmarkLabel("menu.displayMode.remaining".localized(), isSelected: displayMode == .remaining)
            }
        } label: {
            Label("menu.displayMode".localized(), systemImage: "eye")
        }
    }

    private var languageMenu: some View {
        Menu {
            let languages = languageManager.availableLanguages
            if let systemLanguage = languages.first {
                Button { languageManager.setLanguage(systemLanguage) } label: {
                    CheckmarkLabel(systemLanguage.displayName, isSelected: languageManager.currentLanguage == systemLanguage)
                }
            }
            if languages.count > 1 {
                Divider()
                ForEach(languages.dropFirst()) { language in
                    Button { languageManager.setLanguage(language) } label: {
                        CheckmarkLabel(language.displayName, isSelected: languageManager.currentLanguage == language)
                    }
                }
            }
        } label: {
            Label("menu.language".localized(), systemImage: "globe")
        }
    }

    private var wakeUpMenu: some View {
        Menu {
            ForEach(WakeUpScheduler.supportedProviders) { provider in
                Button("\(provider.displayName) " + "menu.wakeUpNow".localized()) {
                    Task { await WakeUpScheduler.shared.triggerWakeUp(for: provider) }
                }
            }
        } label: {
            Label("menu.wakeUp".localized(), systemImage: "alarm")
        }
    }

    private var loginAtStartupButton: some View {
        Button { loginItemManager.setEnabled(!loginItemManager.isEnabled) } label: {
            CheckmarkLabel("wakeUp.startAtLogin".localized(), isSelected: loginItemManager.isEnabled)
        }
    }

    private func presentAboutPanel() {
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
}
