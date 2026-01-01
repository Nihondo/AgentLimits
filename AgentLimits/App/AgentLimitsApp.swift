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
    /// Opens the usage settings page for the specified provider
    static func handleURL(_ url: URL) {
        guard url.scheme == "agentlimits",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        switch url.host {
        case "open-usage":
            // Existing usage limit widget
            if let providerValue = components.queryItems?.first(where: { $0.name == "provider" })?.value,
               let provider = UsageProvider(rawValue: providerValue) {
                NSWorkspace.shared.open(provider.usageURL)
            }
        case "open-token-usage":
            // Token usage widget (ccusage) - open ccusage site
            if let url = CCUsageLinks.siteURL {
                NSWorkspace.shared.open(url)
            }
        default:
            break
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
    @StateObject private var appState = AppSharedState()

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
    @AppStorage(UsageStatusThresholdStore.revisionKey, store: UserDefaults(suiteName: AppGroupConfig.groupId))
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
    @AppStorage(UsageColorKeys.statusGreen, store: UserDefaults(suiteName: AppGroupConfig.groupId))
    private var statusGreenHex: String = ""
    @AppStorage(UsageColorKeys.statusOrange, store: UserDefaults(suiteName: AppGroupConfig.groupId))
    private var statusOrangeHex: String = ""
    @AppStorage(UsageColorKeys.statusRed, store: UserDefaults(suiteName: AppGroupConfig.groupId))
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
        let percent = displayMode.displayPercent(from: window.usedPercent)
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: provider, windowKind: windowKind)
        let level = UsageStatusLevelResolver.level(
            for: percent,
            isRemainingMode: displayMode == .remaining,
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
        Divider() // ------------------------
        Menu {
            Button {
                displayMode = .used
            } label: {
                if displayMode == .used {
                    Label("menu.displayMode.used".localized(), systemImage: "checkmark")
                } else {
                    Text("menu.displayMode.used".localized())
                }
            }
            Button {
                displayMode = .remaining
            } label: {
                if displayMode == .remaining {
                    Label("menu.displayMode.remaining".localized(), systemImage: "checkmark")
                } else {
                    Text("menu.displayMode.remaining".localized())
                }
            }
        } label: {
            Label("menu.displayMode".localized(), systemImage: "eye")
        }
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageManager.setLanguage(language)
                } label: {
                    if languageManager.currentLanguage == language {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            Label("menu.language".localized(), systemImage: "globe")
        }
        Menu {
            ForEach(UsageProvider.allCases) { provider in
                Button("\(provider.displayName) " + "menu.wakeUpNow".localized()) {
                    Task {
                        await WakeUpScheduler.shared.triggerWakeUp(for: provider)
                    }
                }
            }
        } label: {
            Label("menu.wakeUp".localized(), systemImage: "alarm")
        }
        Divider() // ------------------------
        Button {
            loginItemManager.setEnabled(!loginItemManager.isEnabled)
        } label: {
            if loginItemManager.isEnabled {
                Label("wakeUp.startAtLogin".localized(), systemImage: "checkmark")
            } else {
                Text("wakeUp.startAtLogin".localized())
            }
        }
        Divider() // ------------------------
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
}
