// MARK: - AgentLimitsApp.swift
// Main application entry point for AgentLimits menu bar app.
// Provides menu bar UI, settings window, and deep link handling.

import SwiftUI
import AppKit

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
            if let url = URL(string: "https://ccusage.com/") {
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
        MenuBarExtra("AgentLimits", image: .menuBarIcon) {
            MenuBarContentView()
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
