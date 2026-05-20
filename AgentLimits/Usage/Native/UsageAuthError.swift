// MARK: - UsageAuthError.swift
// Unified error sentinels for native Codex/Claude usage fetchers.
// These are surfaced to the UI so it can show a re-auth button instead of a
// generic "fetch failed" message.

import Foundation

/// Errors surfaced by the native (non-WebView) usage fetchers.
///
/// `localizedDescription` is intentionally stable English text — the codex-island
/// contract specifies exact wording (`"auth expired — codex login"` and
/// `"re-login: claude /login"`) so the UI layer can string-match on the
/// sentinel. Localized variants are shown via the dedicated user-facing
/// helpers in `ContentView`, not the raw `localizedDescription`.
enum UsageAuthError: Error, LocalizedError, Equatable {
    /// Codex auth token in `~/.codex/auth.json` is missing or rejected.
    /// Recovery: user runs `codex login`.
    case codexAuthExpired

    /// Codex auth file present but unreadable / malformed.
    case codexAuthUnavailable(reason: String)

    /// Claude token failed (401 even after refresh) — refresh exhausted.
    /// Recovery: user runs `claude /login`.
    case claudeAuthExpired

    /// Claude token returned 403 — scope insufficient (missing `user:profile`).
    /// Recovery REQUIRES a fresh `claude /login` because refresh re-issues the
    /// same scope set.
    case claudeReLogin

    /// Provider returned 429 or a 200 body with `rate_limit_error`.
    case rateLimited

    /// Claude keychain item not found.
    case claudeAuthUnavailable(reason: String)

    /// Unexpected HTTP status from the provider's usage endpoint.
    case httpStatus(code: Int, body: String)

    /// JSON decoding failure.
    case invalidResponse(reason: String)

    /// Outbound HTTP transport failure (DNS, TLS, timeout).
    case transport(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .codexAuthExpired:
            return "auth expired — codex login"
        case .codexAuthUnavailable(let reason):
            return "codex auth unavailable: \(reason)"
        case .claudeAuthExpired:
            return "re-login: claude /login"
        case .claudeReLogin:
            return "re-login: claude /login"
        case .rateLimited:
            return "rate limited"
        case .claudeAuthUnavailable(let reason):
            return "claude auth unavailable: \(reason)"
        case .httpStatus(let code, let body):
            let preview = body.prefix(200)
            return "HTTP \(code): \(preview)"
        case .invalidResponse(let reason):
            return "invalid response: \(reason)"
        case .transport(let error):
            return error.localizedDescription
        }
    }

    /// Returns true when the user must take an action (re-login) to recover.
    var requiresUserReauth: Bool {
        switch self {
        case .codexAuthExpired, .codexAuthUnavailable,
             .claudeAuthExpired, .claudeReLogin, .claudeAuthUnavailable:
            return true
        case .rateLimited, .httpStatus, .invalidResponse, .transport:
            return false
        }
    }

    /// The CLI command the user should run to recover, if any.
    var recoveryCLICommand: String? {
        switch self {
        case .codexAuthExpired, .codexAuthUnavailable:
            return "codex login"
        case .claudeAuthExpired, .claudeReLogin, .claudeAuthUnavailable:
            return "claude /login"
        default:
            return nil
        }
    }

    static func == (lhs: UsageAuthError, rhs: UsageAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.codexAuthExpired, .codexAuthExpired),
             (.claudeAuthExpired, .claudeAuthExpired),
             (.claudeReLogin, .claudeReLogin),
             (.rateLimited, .rateLimited):
            return true
        case (.codexAuthUnavailable(let l), .codexAuthUnavailable(let r)),
             (.claudeAuthUnavailable(let l), .claudeAuthUnavailable(let r)),
             (.invalidResponse(let l), .invalidResponse(let r)):
            return l == r
        case (.httpStatus(let lCode, let lBody), .httpStatus(let rCode, let rBody)):
            return lCode == rCode && lBody == rBody
        case (.transport, .transport):
            return true
        default:
            return false
        }
    }
}
