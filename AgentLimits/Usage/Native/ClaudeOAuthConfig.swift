// MARK: - ClaudeOAuthConfig.swift
// Constants that the Anthropic OAuth/usage flow is contractually pinned to.
// These ARE NOT secrets — `clientID` is the public Claude Code OAuth client
// and is hardcoded in the upstream CLI as well. We reuse it so the user's
// own already-granted session works.

import Foundation

/// Compile-time constants for the Claude Code OAuth flow.
///
/// `claudeCodeCLIVersionFallback` is the bundled fallback. The runtime value is
/// detected from the user's installed Claude Code CLI when possible.
enum ClaudeOAuthConfig {
    /// Reported in `User-Agent: claude-code/<version>`.
    nonisolated static let claudeCodeCLIVersionFallback: String = "2.1.121"

    /// Required OAuth beta gate header.
    nonisolated static let oauthBetaHeader: String = "oauth-2025-04-20"

    /// Public Claude Code OAuth client_id — hardcoded in the upstream CLI.
    nonisolated static let clientIDDefault: String = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// Public Claude Code OAuth client_id, optionally overridden for testing.
    nonisolated static var clientID: String {
        let rawValue = AppGroupDefaults.shared?
            .string(forKey: ClaudeOAuthOverrideKeys.clientID) ?? ""
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? clientIDDefault : trimmedValue
    }

    /// Usage endpoint (gated on User-Agent + Authorization).
    nonisolated static let usageEndpoint: URL = {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            preconditionFailure("Invalid Claude usage endpoint URL")
        }
        return url
    }()

    /// OAuth token endpoint — migrated from console.anthropic.com to platform.claude.com.
    /// The old host still resolves but is not the canonical issuer for fresh tokens.
    nonisolated static let tokenEndpoint: URL = {
        guard let url = URL(string: "https://platform.claude.com/v1/oauth/token") else {
            preconditionFailure("Invalid Claude token endpoint URL")
        }
        return url
    }()

    /// Computed User-Agent string.
    nonisolated static var userAgent: String {
        "claude-code/\(ClaudeCLIVersionResolver.cachedVersion())"
    }

    /// Keychain service name written by `claude /login`.
    nonisolated static let keychainService: String = "Claude Code-credentials"

    /// Environment variable Claude Desktop sets for its child processes.
    nonisolated static let envTokenVariable: String = "CLAUDE_CODE_OAUTH_TOKEN"

    /// Minimum poll interval (seconds) — Anthropic rate-limits aggressively.
    /// Sub-5-minute polling burns the daily quota and triggers `rate_limit_error`
    /// responses for the user's actual Claude Code sessions.
    nonisolated static let minimumPollInterval: TimeInterval = 5 * 60
}
