// MARK: - ClaudeCLILocator.swift
// Locates and detached-spawns the `claude` and `codex` binaries.
// Path resolution is delegated to CLICommandPathResolver so native auth,
// Advanced Settings, Wake Up, and ccusage all observe the same CLI path rules.

import Foundation
import OSLog

/// Resolves and launches Claude Code / Codex CLIs for native re-auth flows.
enum ClaudeCLILocator {
    /// Returns the first matching `claude` binary, or nil.
    nonisolated static func locateClaudeBinary() async -> String? {
        await CLICommandPathResolver.resolveExecutablePath(for: .claude)
    }

    /// Returns the first matching `codex` binary, or nil.
    nonisolated static func locateCodexBinary() async -> String? {
        await CLICommandPathResolver.resolveExecutablePath(for: .codex)
    }

    /// Detached-spawns the Claude Code re-auth flow. Returns true if the
    /// process was launched. The CLI handles browser + callback + keychain
    /// write; we recover automatically on the next poll once the rotated
    /// token appears in the keychain.
    @discardableResult
    nonisolated static func launchClaudeLogin() async -> Bool {
        guard let claudePath = await locateClaudeBinary() else {
            Logger.usage.error("ClaudeCLILocator: claude binary not resolved by CLI path settings or login shell")
            return false
        }
        return spawnDetached(executablePath: claudePath, arguments: ["/login"])
    }

    /// Detached-spawns the Codex re-auth flow. Returns true on launch.
    @discardableResult
    nonisolated static func launchCodexLogin() async -> Bool {
        guard let codexPath = await locateCodexBinary() else {
            Logger.usage.error("ClaudeCLILocator: codex binary not resolved by CLI path settings or login shell")
            return false
        }
        return spawnDetached(executablePath: codexPath, arguments: ["login"])
    }

    nonisolated private static func spawnDetached(executablePath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            Logger.usage.error("ClaudeCLILocator: spawnDetached failed for \(executablePath): \(error.localizedDescription)")
            return false
        }
    }
}
