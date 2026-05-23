// MARK: - CLICommandPathResolver+Shell.swift
// Shell-based executable path resolution for the app target.

import Foundation

extension CLICommandPathResolver {
    /// Resolves an executable path for the given CLI command kind.
    /// Full-path overrides take precedence. Without an override, the user's
    /// login shell resolves the command with the same PATH handling used by
    /// CLI execution features.
    /// - Parameter kind: CLI command kind to resolve.
    /// - Returns: Resolved path or nil when not found.
    static func resolveExecutablePath(for kind: CLICommandKind) async -> String? {
        if let overridePath = resolveOverridePath(for: kind) {
            guard CLICommandPathValidator.isExecutablePathValid(overridePath) else {
                return nil
            }
            return (overridePath as NSString).expandingTildeInPath
        }
        return await resolveExecutablePath(commandName: kind.rawValue)
    }

    /// Resolves an executable path for the given command name using the login shell.
    /// - Parameter commandName: Command name to resolve via `command -v`.
    /// - Returns: Resolved path or nil when not found.
    static func resolveExecutablePath(commandName: String) async -> String? {
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
}
