// MARK: - SettingsTabView.swift
// Unified settings view with sidebar navigation (macOS System Settings style).

import SwiftUI

// MARK: - Settings Tab Enum

enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case usage
    case wakeUp
    case threshold
    case pacemaker
    case ccusage
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: return "tab.usage".localized()
        case .wakeUp: return "tab.wakeUp".localized()
        case .threshold: return "tab.notification".localized()
        case .pacemaker: return "tab.pacemaker".localized()
        case .ccusage: return "tab.ccusage".localized()
        case .advanced: return "tab.advanced".localized()
        }
    }

    var iconName: String {
        switch self {
        case .usage: return "chart.pie"
        case .wakeUp: return "alarm"
        case .threshold: return "bell"
        case .pacemaker: return "gauge"
        case .ccusage: return "chart.bar"
        case .advanced: return "gearshape"
        }
    }
}

// MARK: - Settings Tab View

struct SettingsTabView: View {
    @AppStorage("selectedSettingsTab") private var selectedTabRaw: String = SettingsTab.usage.rawValue
    let viewModel: UsageViewModel
    let webViewPool: UsageWebViewPool
    let tokenUsageViewModel: TokenUsageViewModel

    private var selectedTabBinding: Binding<SettingsTab?> {
        Binding(
            get: { SettingsTab(rawValue: selectedTabRaw) ?? .usage },
            set: { newValue in
                if let newValue {
                    selectedTabRaw = newValue.rawValue
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: selectedTabBinding) { tab in
                Label(tab.title, systemImage: tab.iconName)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detailContent
        }
        .frame(
            minWidth: DesignTokens.WindowSize.minWidth,
            minHeight: DesignTokens.WindowSize.minHeight
        )
        .navigationTitle("window.settings.title".localized())
        .onAppear {
            configureWindowButtons()
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch SettingsTab(rawValue: selectedTabRaw) ?? .usage {
        case .usage:
            ContentView(viewModel: viewModel, webViewPool: webViewPool)
        case .wakeUp:
            WakeUpSettingsView(scheduler: .shared)
        case .threshold:
            ThresholdSettingsView(manager: .shared)
        case .pacemaker:
            PacemakerSettingsView()
        case .ccusage:
            CCUsageSettingsView(viewModel: tokenUsageViewModel)
        case .advanced:
            CLICommandSettingsView()
        }
    }

    // MARK: - Private Methods

    private func configureWindowButtons() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) else { return }
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }
}
