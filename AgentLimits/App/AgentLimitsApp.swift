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
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])
        .commandsRemoved()
    }
}

// MARK: - Menu Bar Label

/// Dynamic menu bar label showing usage status for enabled providers.
/// Uses debouncing to avoid excessive ImageRenderer calls when multiple properties change rapidly.
private struct MenuBarLabelView: View {
    @EnvironmentObject private var appState: AppSharedState
    @AppStorage(UserDefaultsKeys.menuBarStatusCodexEnabled) private var codexEnabled = false
    @AppStorage(UserDefaultsKeys.menuBarStatusClaudeEnabled) private var claudeEnabled = false
    @AppStorage(UserDefaultsKeys.displayMode) private var displayMode: UsageDisplayMode = .used
    @AppStorage(UsageStatusThresholdStore.revisionKey, store: AppGroupDefaults.shared)
    private var thresholdRevision: Double = 0
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
        .onChange(of: displayMode) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: colorScheme) { _, _ in
            scheduleImageUpdate()
        }
        .onChange(of: thresholdRevision) { _, _ in
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
        let content = MenuBarLabelContentView(
            codexSnapshot: codexSnapshot,
            claudeSnapshot: claudeSnapshot,
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
    @AppStorage(UsageColorKeys.statusGreen, store: AppGroupDefaults.shared)
    private var statusGreenHex: String = ""
    @AppStorage(UsageColorKeys.statusOrange, store: AppGroupDefaults.shared)
    private var statusOrangeHex: String = ""
    @AppStorage(UsageColorKeys.statusRed, store: AppGroupDefaults.shared)
    private var statusRedHex: String = ""

    var body: some View {
        HStack(spacing: 2) {
            Text(formatPercentText(primaryWindow))
                .foregroundColor(resolveStatusColor(primaryWindow, windowKind: .primary))
            Text("/")
                .foregroundStyle(.secondary)
            Text(formatPercentText(secondaryWindow))
                .foregroundColor(resolveStatusColor(secondaryWindow, windowKind: .secondary))
        }
        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func formatPercentText(_ window: UsageWindow?) -> String {
        let percent = window.map { displayMode.displayPercent(from: $0.usedPercent) }
        return UsagePercentFormatter.formatPercentText(percent)
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

/// Menu bar dropdown content with settings, display mode, and language options
private struct MenuBarContentView: View {
    @AppStorage(UserDefaultsKeys.displayMode) private var displayMode: UsageDisplayMode = .used
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppSharedState
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var loginItemManager = LoginItemManager.shared

    var body: some View {
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
        }
    }

    // MARK: - Menu Sections

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
            ForEach(UsageProvider.allCases) { provider in
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
        let repositoryURLString = "https://github.com/Nihondo/AgentLimits"
        let creditsText = "\(copyright)\nGitHub: \(repositoryURLString)"
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
