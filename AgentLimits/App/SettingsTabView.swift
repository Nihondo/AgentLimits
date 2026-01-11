// MARK: - SettingsTabView.swift
// Unified settings view with tab-based navigation.
// Combines usage status, Wake Up settings, and threshold notification settings.

import SwiftUI

// MARK: - Settings Tab Enum

enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case usage
    case wakeUp
    case threshold
    case ccusage
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: return "tab.usage".localized()
        case .wakeUp: return "tab.wakeUp".localized()
        case .threshold: return "tab.notification".localized()
        case .ccusage: return "tab.ccusage".localized()
        case .advanced: return "tab.advanced".localized()
        }
    }

    var iconName: String {
        switch self {
        case .usage: return "chart.pie"
        case .wakeUp: return "alarm"
        case .threshold: return "bell"
        case .ccusage: return "chart.bar"
        case .advanced: return "gearshape"
        }
    }
}

// MARK: - Settings Toolbar Button

private struct SettingsToolbarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 22))
                    .frame(width: 28, height: 28)
                Text(tab.title)
                    .font(.system(size: 11))
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Tab View

struct SettingsTabView: View {
    @AppStorage("selectedSettingsTab") private var selectedTabRaw: String = SettingsTab.usage.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let viewModel: UsageViewModel
    let webViewPool: UsageWebViewPool
    let tokenUsageViewModel: TokenUsageViewModel

    private var selectedTab: SettingsTab {
        get { SettingsTab(rawValue: selectedTabRaw) ?? .usage }
        set { selectedTabRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ツールバー
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsToolbarButton(tab: tab, isSelected: selectedTab == tab) {
                        selectTab(tab)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)

            Divider()

            // コンテンツ
            Group {
                switch selectedTab {
                case .usage:
                    ContentView(viewModel: viewModel, webViewPool: webViewPool)
                case .wakeUp:
                    WakeUpSettingsView(scheduler: .shared)
                case .threshold:
                    ThresholdSettingsView(manager: .shared)
                case .ccusage:
                    CCUsageSettingsView(viewModel: tokenUsageViewModel)
                case .advanced:
                    CLICommandSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedTab)
        }
        .frame(
            minWidth: DesignTokens.WindowSize.minWidth,
            minHeight: DesignTokens.WindowSize.minHeight
        )
        .navigationTitle(selectedTab.title)
        .onAppear {
            configureWindowButtons()
        }
    }

    // MARK: - Private Methods

    private func configureWindowButtons() {
        guard let window = NSApp.windows.first(where: { $0.title == selectedTab.title || $0.identifier?.rawValue == "settings" }) else { return }
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    private func selectTab(_ tab: SettingsTab) {
        let animation = Animation.easeInOut(duration: 0.15)
        if reduceMotion {
            selectedTabRaw = tab.rawValue
        } else {
            withAnimation(animation) {
                selectedTabRaw = tab.rawValue
            }
        }
    }
}
