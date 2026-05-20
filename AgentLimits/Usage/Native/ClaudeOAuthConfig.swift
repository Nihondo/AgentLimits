// MARK: - ClaudeOAuthConfig.swift
// Constants that the Anthropic OAuth/usage flow is contractually pinned to.
// These ARE NOT secrets — `clientID` is the public Claude Code OAuth client
// and is hardcoded in the upstream CLI as well. We reuse it so the user's
// own already-granted session works.

import Foundation

/// Compile-time constants for the Claude Code OAuth flow.
///
/// `claudeCodeCLIVersion` is exposed as a settable constant so we can bump it
/// without redeploying — Anthropic gates `/api/oauth/usage` on the
/// `claude-code/X.Y.Z` User-Agent shape. A wrong version may still 401.
enum ClaudeOAuthConfig {
    /// Reported in `User-Agent: claude-code/<version>`.
    /// Bump in lockstep with whatever Anthropic's current Claude Code CLI ships.
    static let claudeCodeCLIVersion: String = "2.1.121"

    /// Required OAuth beta gate header.
    static let oauthBetaHeader: String = "oauth-2025-04-20"

    /// Public Claude Code OAuth client_id — hardcoded in the upstream CLI.
    static let clientID: String = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// Usage endpoint (gated on User-Agent + Authorization).
    static let usageEndpoint: URL = {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            preconditionFailure("Invalid Claude usage endpoint URL")
        }
        return url
    }()

    /// OAuth token endpoint — migrated from console.anthropic.com to platform.claude.com.
    /// The old host still resolves but is not the canonical issuer for fresh tokens.
    static let tokenEndpoint: URL = {
        guard let url = URL(string: "https://platform.claude.com/v1/oauth/token") else {
            preconditionFailure("Invalid Claude token endpoint URL")
        }
        return url
    }()

    /// Computed User-Agent string.
    static var userAgent: String {
        "claude-code/\(claudeCodeCLIVersion)"
    }

    /// Keychain service name written by `claude /login`.
    static let keychainService: String = "Claude Code-credentials"

    /// Environment variable Claude Desktop sets for its child processes.
    static let envTokenVariable: String = "CLAUDE_CODE_OAUTH_TOKEN"

    /// Minimum poll interval (seconds) — Anthropic rate-limits aggressively.
    /// Sub-5-minute polling burns the daily quota and triggers `rate_limit_error`
    /// responses for the user's actual Claude Code sessions.
    static let minimumPollInterval: TimeInterval = 5 * 60
}
