// MARK: - SettingsComponents.swift
// Shared settings UI components.

import SwiftUI

struct SettingsHeaderView: View {
    let titleText: String
    let descriptionText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.title2)
                .bold()
            Text(descriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct RefreshIntervalPickerRow: View {
    let labelKey: String
    let showsLabel: Bool
    @Binding var refreshIntervalMinutes: Int

    init(
        labelKey: String = "refreshInterval.label",
        showsLabel: Bool = true,
        refreshIntervalMinutes: Binding<Int>
    ) {
        self.labelKey = labelKey
        self.showsLabel = showsLabel
        self._refreshIntervalMinutes = refreshIntervalMinutes
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsLabel {
                Text(labelKey.localized())
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            Picker(
                labelKey.localized(),
                selection: makeRefreshIntervalBinding()
            ) {
                ForEach(RefreshIntervalConfig.supportedMinutes, id: \.self) { minutes in
                    Text("refreshInterval.minutesFormat".localized(minutes))
                        .tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(Text(labelKey.localized()))
        }
        .onAppear {
            refreshIntervalMinutes = RefreshIntervalConfig.normalizedMinutes(refreshIntervalMinutes)
        }
    }

    private func makeRefreshIntervalBinding() -> Binding<Int> {
        Binding(
            get: { RefreshIntervalConfig.normalizedMinutes(refreshIntervalMinutes) },
            set: { newValue in
                refreshIntervalMinutes = RefreshIntervalConfig.normalizedMinutes(newValue)
            }
        )
    }
}

/// Scrollable container for settings content.
struct SettingsScrollContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
                content
            }
            .padding(DesignTokens.Spacing.large)
        }
    }
}

/// Form section wrapper with optional header/footer text.
struct SettingsFormSection<Content: View>: View {
    let title: String?
    let footerText: String?
    let content: Content

    init(
        title: String? = nil,
        footerText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footerText = footerText
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            if let title {
                Text(title)
                    .font(.headline)
            }
        } footer: {
            if let footerText {
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Supported button styling options for settings UI.
enum SettingsButtonKind {
    case primary
    case secondary
    case destructive
}

/// Consistent button styling for settings UI.
struct SettingsButtonStyle: ViewModifier {
    let kind: SettingsButtonKind

    func body(content: Content) -> some View {
        switch kind {
        case .primary:
            content.buttonStyle(.borderedProminent)
        case .secondary:
            content.buttonStyle(.bordered)
        case .destructive:
            content.buttonStyle(.bordered)
                .tint(.red)
        }
    }
}

extension View {
    /// Applies a consistent settings button style.
    func settingsButtonStyle(_ kind: SettingsButtonKind) -> some View {
        modifier(SettingsButtonStyle(kind: kind))
    }
}

/// Status indicator levels for settings UI.
enum SettingsStatusLevel {
    case success
    case warning
    case error
    case inactive

    var color: Color {
        switch self {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .inactive:
            return .gray
        }
    }
}

/// Status indicator with a colored dot and text label.
struct SettingsStatusIndicator: View {
    let text: String
    let level: SettingsStatusLevel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(level.color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
