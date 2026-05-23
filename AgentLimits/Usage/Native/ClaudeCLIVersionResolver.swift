// MARK: - ClaudeCLIVersionResolver.swift
// Detects the installed Claude Code CLI version used for Anthropic OAuth
// User-Agent compatibility.

import Foundation
import OSLog

/// Claude Code CLI のバージョンを検出し、User-Agent 用にキャッシュする。
enum ClaudeCLIVersionResolver {
    nonisolated private static let cachedVersionKey = "claude_cli_version_cached"
    nonisolated private static let fetchedAtKey = "claude_cli_version_fetched_at"
    nonisolated private static let cacheTTL: TimeInterval = 24 * 60 * 60

    /// キャッシュ済みバージョンを返す。未検出時は同梱 fallback を返す。
    nonisolated static func cachedVersion() -> String {
        let rawValue = AppGroupDefaults.shared?.string(forKey: cachedVersionKey) ?? ""
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? ClaudeOAuthConfig.claudeCodeCLIVersionFallback : trimmedValue
    }

    /// TTL が切れている場合のみ Claude CLI のバージョンを再検出する。
    nonisolated static func refreshIfNeeded() async {
        let defaults = AppGroupDefaults.shared
        let fetchedAt = defaults?.object(forKey: fetchedAtKey) as? Date
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < cacheTTL {
            return
        }
        await forceRefresh()
    }

    /// Claude CLI のバージョンを即時再検出する。
    nonisolated static func forceRefresh() async {
        guard let claudePath = ClaudeCLILocator.locateClaudeBinary() else {
            Logger.usage.error("ClaudeCLIVersionResolver: claude binary not found")
            return
        }
        do {
            let output = try await runVersionCommand(executablePath: claudePath)
            guard let version = extractVersion(from: output) else {
                Logger.usage.error("ClaudeCLIVersionResolver: could not parse version from '\(output)'")
                return
            }
            let defaults = AppGroupDefaults.shared
            defaults?.set(version, forKey: cachedVersionKey)
            defaults?.set(Date(), forKey: fetchedAtKey)
        } catch {
            Logger.usage.error("ClaudeCLIVersionResolver: claude --version failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func runVersionCommand(executablePath: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["--version"]
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.terminationHandler = { process in
                let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    let stderrText = String(data: stderr, encoding: .utf8) ?? ""
                    continuation.resume(
                        throwing: VersionCommandError.failed(
                            exitCode: process.terminationStatus,
                            stderr: stderrText
                        )
                    )
                    return
                }
                let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
                let stderrText = String(data: stderr, encoding: .utf8) ?? ""
                continuation.resume(returning: stdoutText + "\n" + stderrText)
            }
        }
    }

    nonisolated private static func extractVersion(from text: String) -> String? {
        let pattern = #"\d+\.\d+\.\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }

    private enum VersionCommandError: LocalizedError {
        case failed(exitCode: Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .failed(let exitCode, let stderr):
                return "claude --version failed (\(exitCode)): \(stderr.prefix(200))"
            }
        }
    }
}
