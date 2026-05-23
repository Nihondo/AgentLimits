// MARK: - ClaudeCLILocator.swift
// Locates the `claude` (and `codex`) binary in well-known install locations
// that GUI apps cannot discover via PATH. LaunchServices hands GUI processes
// a stripped PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), so `which claude` misses
// every Homebrew/Bun/nvm install.

import Foundation
import OSLog

/// Probes well-known CLI install paths for the Claude Code / Codex CLIs.
enum ClaudeCLILocator {
    /// Returns the first matching `claude` binary, or nil.
    nonisolated static func locateClaudeBinary() -> String? {
        // Honor user override first.
        let override = CLICommandPathResolver.resolveExecutable(for: .claude, defaultName: "claude")
        if override != "claude", CLICommandPathValidator.isExecutablePathValid(override) {
            return (override as NSString).expandingTildeInPath
        }
        return locate(binaryName: "claude")
    }

    /// Returns the first matching `codex` binary, or nil.
    nonisolated static func locateCodexBinary() -> String? {
        let override = CLICommandPathResolver.resolveExecutable(for: .codex, defaultName: "codex")
        if override != "codex", CLICommandPathValidator.isExecutablePathValid(override) {
            return (override as NSString).expandingTildeInPath
        }
        return locate(binaryName: "codex")
    }

    /// Probes the codex-island canonical install paths in priority order.
    nonisolated private static func locate(binaryName: String) -> String? {
        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/\(binaryName)",
            "/usr/local/bin/\(binaryName)",
            "\(home)/.bun/bin/\(binaryName)",
            "\(home)/.npm-global/bin/\(binaryName)",
            "\(home)/.local/bin/\(binaryName)"
        ]
        if let nvmPath = highestNvmVersionPath(binaryName: binaryName, home: home) {
            candidates.append(nvmPath)
        }
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Finds the highest `~/.nvm/versions/node/<version>/bin/<binary>` if any.
    nonisolated private static func highestNvmVersionPath(binaryName: String, home: String) -> String? {
        let nvmDir = "\(home)/.nvm/versions/node"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) else {
            return nil
        }
        let sorted = entries.sorted { lhs, rhs in
            compareNodeVersion(lhs, rhs) == .orderedDescending
        }
        for version in sorted {
            let path = "\(nvmDir)/\(version)/bin/\(binaryName)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Detached-spawns the Claude Code re-auth flow. Returns true if the
    /// process was launched. The CLI handles browser + callback + keychain
    /// write; we recover automatically on the next poll once the rotated
    /// token appears in the keychain.
    @discardableResult
    nonisolated static func launchClaudeLogin() -> Bool {
        guard let claudePath = locateClaudeBinary() else {
            Logger.usage.error("ClaudeCLILocator: claude binary not found in known locations")
            return false
        }
        return spawnDetached(executablePath: claudePath, arguments: ["/login"])
    }

    /// Detached-spawns the Codex re-auth flow. Returns true on launch.
    @discardableResult
    nonisolated static func launchCodexLogin() -> Bool {
        guard let codexPath = locateCodexBinary() else {
            Logger.usage.error("ClaudeCLILocator: codex binary not found in known locations")
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

    nonisolated private static func compareNodeVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = parseNodeVersion(lhs)
        let rhsParts = parseNodeVersion(rhs)
        for index in 0..<max(lhsParts.count, rhsParts.count) {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0
            if lhsValue > rhsValue { return .orderedDescending }
            if lhsValue < rhsValue { return .orderedAscending }
        }
        return lhs.localizedStandardCompare(rhs)
    }

    nonisolated private static func parseNodeVersion(_ version: String) -> [Int] {
        let normalized = version.drop(while: { $0 == "v" })
        return normalized.split(separator: ".").compactMap { Int($0) }
    }
}
