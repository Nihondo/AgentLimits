// MARK: - ClaudeKeychainStore.swift
// Reads/writes the `Claude Code-credentials` keychain item via /usr/bin/security.
// Uses Process directly with argv (no shell) so the JSON password value is
// passed safely without shell-quoting hazards.
//
// CRITICAL: Anthropic rotates BOTH the access_token AND the refresh_token on
// every refresh. The new pair MUST be written back into this keychain item
// or Claude Code itself will 401 on its NEXT refresh and force the user to
// re-run `claude /login`.

import Foundation

/// The decrypted payload stored inside the keychain item.
/// Wire format is JSON; field names match what Claude Code itself writes.
struct ClaudeCredentialsPayload: Codable, Equatable {
    /// expiresAt is ms-since-epoch (not seconds).
    struct ClaudeAiOAuth: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        /// Milliseconds since 1970-01-01 00:00:00 UTC.
        var expiresAt: Int64
        var subscriptionType: String?
        var scopes: [String]?
    }
    var claudeAiOauth: ClaudeAiOAuth
}

/// Reader/writer for the `Claude Code-credentials` keychain item.
enum ClaudeKeychainStore {
    /// In-memory cache of the discovered account name so we don't re-shell on
    /// every refresh. The account name is whatever string the user's
    /// `claude /login` happened to write — it isn't fixed.
    private static var cachedAccount: String?

    /// Loads the current credentials payload, alongside the keychain account
    /// name (needed for write-back).
    static func loadCredentials() throws -> (payload: ClaudeCredentialsPayload, account: String) {
        let account = try resolveAccount()
        let json = try readPasswordJSON(account: account)
        let decoded: ClaudeCredentialsPayload
        do {
            decoded = try JSONDecoder().decode(ClaudeCredentialsPayload.self, from: Data(json.utf8))
        } catch {
            throw UsageAuthError.claudeAuthUnavailable(
                reason: "keychain payload malformed: \(error.localizedDescription)"
            )
        }
        return (decoded, account)
    }

    /// Writes back a credentials payload, preserving the existing account name.
    /// Uses `add-generic-password -U` to update the existing item in place
    /// (preserves keychain ACLs unlike a delete-then-add).
    static func writeCredentials(_ payload: ClaudeCredentialsPayload, account: String) throws {
        let encoded: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoded = try encoder.encode(payload)
        } catch {
            throw UsageAuthError.claudeAuthUnavailable(
                reason: "encode credentials: \(error.localizedDescription)"
            )
        }
        guard let json = String(data: encoded, encoding: .utf8) else {
            throw UsageAuthError.claudeAuthUnavailable(reason: "non-utf8 credentials JSON")
        }
        let result = runSecurity(arguments: [
            "add-generic-password",
            "-U",
            "-s", ClaudeOAuthConfig.keychainService,
            "-a", account,
            "-w", json
        ])
        if result.exitCode != 0 {
            throw UsageAuthError.claudeAuthUnavailable(
                reason: "security add-generic-password failed (\(result.exitCode)): \(result.stderr.prefix(200))"
            )
        }
        cachedAccount = account
    }

    /// Resolves the keychain account name. Caches the result.
    /// `security find-generic-password -s "<service>"` prints a metadata block
    /// containing an `"acct"<blob>="<value>"` line. We parse `<value>` from there.
    private static func resolveAccount() throws -> String {
        if let cached = cachedAccount {
            return cached
        }
        let result = runSecurity(arguments: [
            "find-generic-password",
            "-s", ClaudeOAuthConfig.keychainService
        ])
        if result.exitCode != 0 {
            throw UsageAuthError.claudeAuthUnavailable(
                reason: "keychain item '\(ClaudeOAuthConfig.keychainService)' not found — run claude /login"
            )
        }
        // `security` historically printed metadata to stderr; modern versions
        // route to stdout. Parse whichever has the acct line.
        let combined = result.stdout + "\n" + result.stderr
        guard let account = parseAcctValue(from: combined) else {
            throw UsageAuthError.claudeAuthUnavailable(
                reason: "could not parse account name from security output"
            )
        }
        cachedAccount = account
        return account
    }

    private static func readPasswordJSON(account: String) throws -> String {
        let result = runSecurity(arguments: [
            "find-generic-password",
            "-s", ClaudeOAuthConfig.keychainService,
            "-a", account,
            "-w"
        ])
        if result.exitCode != 0 {
            throw UsageAuthError.claudeAuthUnavailable(
                reason: "keychain read failed (\(result.exitCode)): \(result.stderr.prefix(200))"
            )
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UsageAuthError.claudeAuthUnavailable(reason: "empty keychain payload")
        }
        return trimmed
    }

    /// Parses `"acct"<blob>="value"` from the metadata block.
    /// Both quoted and hex-blob forms exist; only the quoted variant is used
    /// by Claude Code, which is the only producer of this keychain item.
    private static func parseAcctValue(from text: String) -> String? {
        // Find a line containing `"acct"<...>="..."` and extract the quoted value.
        for line in text.split(whereSeparator: \.isNewline) {
            let lineStr = String(line)
            guard lineStr.contains("\"acct\"") else { continue }
            // Look for `="..."` after the acct marker.
            guard let equalsIdx = lineStr.range(of: "=\"") else { continue }
            let afterEquals = lineStr[equalsIdx.upperBound...]
            guard let closeQuote = afterEquals.firstIndex(of: "\"") else { continue }
            return String(afterEquals[..<closeQuote])
        }
        return nil
    }

    // MARK: - /usr/bin/security subprocess

    private struct SecurityResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Runs /usr/bin/security with argv — no shell, no quoting hazards.
    private static func runSecurity(arguments: [String]) -> SecurityResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            return SecurityResult(stdout: "", stderr: "launch failed: \(error.localizedDescription)", exitCode: -1)
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return SecurityResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
