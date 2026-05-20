// MARK: - CodexAuthStore.swift
// Reads the Codex CLI auth bundle from `~/.codex/auth.json` and returns the
// current `tokens.access_token`. The Codex CLI rotates this on its own — we
// only read it. On 401 from the usage endpoint the caller surfaces
// `UsageAuthError.codexAuthExpired` and the user runs `codex login`.

import Foundation

/// Reads the Codex CLI's on-disk auth bundle.
enum CodexAuthStore {
    /// Absolute path to the Codex CLI auth file (tilde-expanded).
    static var authFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".codex/auth.json", isDirectory: false)
    }

    /// Returns the current access token, or throws `UsageAuthError` describing why not.
    static func loadAccessToken() throws -> String {
        let url = authFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageAuthError.codexAuthUnavailable(reason: "missing ~/.codex/auth.json — run codex login")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw UsageAuthError.codexAuthUnavailable(
                reason: "cannot read auth.json: \(error.localizedDescription)"
            )
        }
        let payload: CodexAuthPayload
        do {
            payload = try JSONDecoder().decode(CodexAuthPayload.self, from: data)
        } catch {
            throw UsageAuthError.codexAuthUnavailable(
                reason: "malformed auth.json: \(error.localizedDescription)"
            )
        }
        guard let token = payload.tokens?.access_token, !token.isEmpty else {
            throw UsageAuthError.codexAuthUnavailable(reason: "no access_token in auth.json — run codex login")
        }
        return token
    }

    private struct CodexAuthPayload: Decodable {
        struct Tokens: Decodable {
            let access_token: String?
        }
        let tokens: Tokens?
    }
}
