// MARK: - CLICommandSettingsView.swift
// Detailed settings for overriding CLI command full paths.

import SwiftUI
import WidgetKit

@MainActor
struct CLICommandSettingsView: View {
    @AppStorage(
        CLICommandPathKeys.codex,
        store: UserDefaults(suiteName: AppGroupConfig.groupId)
    ) private var codexCommandPathText: String = ""

    @AppStorage(
        CLICommandPathKeys.claude,
        store: UserDefaults(suiteName: AppGroupConfig.groupId)
    ) private var claudeCommandPathText: String = ""

    @AppStorage(
        CLICommandPathKeys.npx,
        store: UserDefaults(suiteName: AppGroupConfig.groupId)
    ) private var npxCommandPathText: String = ""

    @State private var resolvedPaths: [CLICommandKind: String] = [:]
    @State private var donutColor: Color = UsageColorSettings.loadDonutColor()
    @State private var isDonutColorByUsage: Bool = UsageColorSettings.loadDonutUseStatus()
    @State private var statusGreenColor: Color = UsageColorSettings.loadStatusGreenColor()
    @State private var statusOrangeColor: Color = UsageColorSettings.loadStatusOrangeColor()
    @State private var statusRedColor: Color = UsageColorSettings.loadStatusRedColor()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            Divider()
            SettingsSection(title: "cliPaths.sectionTitle".localized()) {
                commandPathSection
            }
            Divider()
            SettingsSection(title: "cliColors.title".localized()) {
                colorSettingsSection
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 420)
        .onAppear {
            refreshAllResolvedPaths()
            reloadColorSettings()
        }
        .onChange(of: codexCommandPathText) { _, _ in
            refreshResolvedPath(for: .codex, commandName: "codex", overrideText: codexCommandPathText)
        }
        .onChange(of: claudeCommandPathText) { _, _ in
            refreshResolvedPath(for: .claude, commandName: "claude", overrideText: claudeCommandPathText)
        }
        .onChange(of: npxCommandPathText) { _, _ in
            refreshResolvedPath(for: .npx, commandName: "npx", overrideText: npxCommandPathText)
        }
        .onChange(of: donutColor) { _, _ in
            UsageColorSettings.saveDonutColor(donutColor)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: isDonutColorByUsage) { _, _ in
            UsageColorSettings.saveDonutUseStatus(isDonutColorByUsage)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: statusGreenColor) { _, _ in
            UsageColorSettings.saveStatusGreenColor(statusGreenColor)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: statusOrangeColor) { _, _ in
            UsageColorSettings.saveStatusOrangeColor(statusOrangeColor)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: statusRedColor) { _, _ in
            UsageColorSettings.saveStatusRedColor(statusRedColor)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("advancedSettings.title".localized())
                .font(.title2)
                .bold()
            Text("advancedSettings.description".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var commandPathSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommandPathRow(
                title: "cliPaths.codex".localized(),
                placeholder: "cliPaths.codex.placeholder".localized(),
                commandPathText: $codexCommandPathText,
                resolvedPathText: resolvedPathText(for: .codex),
                isResolved: isResolvedPath(for: .codex)
            )
            CommandPathRow(
                title: "cliPaths.claude".localized(),
                placeholder: "cliPaths.claude.placeholder".localized(),
                commandPathText: $claudeCommandPathText,
                resolvedPathText: resolvedPathText(for: .claude),
                isResolved: isResolvedPath(for: .claude)
            )
            CommandPathRow(
                title: "cliPaths.npx".localized(),
                placeholder: "cliPaths.npx.placeholder".localized(),
                commandPathText: $npxCommandPathText,
                resolvedPathText: resolvedPathText(for: .npx),
                isResolved: isResolvedPath(for: .npx)
            )
            Text("cliPaths.note".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var colorSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ColorPicker("cliColors.donut".localized(), selection: $donutColor, supportsOpacity: false)
                    .disabled(isDonutColorByUsage)
                Toggle("cliColors.donutUseStatus".localized(), isOn: $isDonutColorByUsage)
                    .toggleStyle(.switch)
            }
            ColorPicker("cliColors.green".localized(), selection: $statusGreenColor, supportsOpacity: false)
            ColorPicker("cliColors.orange".localized(), selection: $statusOrangeColor, supportsOpacity: false)
            ColorPicker("cliColors.red".localized(), selection: $statusRedColor, supportsOpacity: false)

            HStack {
                Spacer()
                Button("cliColors.reset".localized()) {
                    resetUsageColors()
                }
            }

            Text("cliColors.note".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func resolvedPathText(for kind: CLICommandKind) -> String {
        resolvedPaths[kind] ?? "cliPaths.notFound".localized()
    }

    private func isResolvedPath(for kind: CLICommandKind) -> Bool {
        resolvedPaths[kind] != nil
    }

    private func refreshAllResolvedPaths() {
        refreshResolvedPath(for: .codex, commandName: "codex", overrideText: codexCommandPathText)
        refreshResolvedPath(for: .claude, commandName: "claude", overrideText: claudeCommandPathText)
        refreshResolvedPath(for: .npx, commandName: "npx", overrideText: npxCommandPathText)
    }

    private func reloadColorSettings() {
        donutColor = UsageColorSettings.loadDonutColor()
        isDonutColorByUsage = UsageColorSettings.loadDonutUseStatus()
        statusGreenColor = UsageColorSettings.loadStatusGreenColor()
        statusOrangeColor = UsageColorSettings.loadStatusOrangeColor()
        statusRedColor = UsageColorSettings.loadStatusRedColor()
    }

    private func resetUsageColors() {
        UsageColorSettings.resetToDefaults()
        reloadColorSettings()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshResolvedPath(
        for kind: CLICommandKind,
        commandName: String,
        overrideText: String
    ) {
        let trimmedOverride = overrideText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let resolvedPath: String?
            if trimmedOverride.isEmpty {
                resolvedPath = await resolveCommandPath(for: commandName)
            } else {
                resolvedPath = validateExecutablePath(trimmedOverride) ? trimmedOverride : nil
            }
            await MainActor.run {
                if let resolvedPath, !resolvedPath.isEmpty {
                    resolvedPaths[kind] = resolvedPath
                } else {
                    resolvedPaths[kind] = nil
                }
            }
        }
    }

    private func resolveCommandPath(for commandName: String) async -> String? {
        do {
            let output = try await ShellExecutor(timeout: 5).executeString(
                command: "command -v \(commandName)"
            )
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    private func validateExecutablePath(_ path: String) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory)
        guard fileExists, !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: expandedPath)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
    }
}

private struct CommandPathRow: View {
    let title: String
    let placeholder: String
    @Binding var commandPathText: String
    let resolvedPathText: String
    let isResolved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            TextField(placeholder, text: $commandPathText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                Image(systemName: isResolved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isResolved ? .green : .red)
                Text("cliPaths.resolvedLabel".localized())
                    .font(.footnote)
                    .foregroundStyle(.primary)
                Text(resolvedPathText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
    }
}

#Preview {
    CLICommandSettingsView()
}
