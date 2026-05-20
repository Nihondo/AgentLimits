// MARK: - CodexUsageFetcher.swift
// Native Codex (ChatGPT) usage fetcher. Reads the access token written by the
// Codex CLI at `~/.codex/auth.json` and calls the backend usage endpoint
// directly via URLSession — no WKWebView, no JS injection.
//
// The Codex CLI rotates its own tokens; we never refresh on our side.
// On HTTP 401 the user must run `codex login`, which we surface via
// `UsageAuthError.codexAuthExpired`.

import Foundation

// MARK: - API Response Models

/// Response structure from ChatGPT Codex usage API.
struct CodexUsageResponse: Codable {
    struct RateLimit: Codable {
        struct Window: Codable {
            let used_percent: Double?
            let limit_window_seconds: Double?
            let reset_after_seconds: Double?
            /// epoch-seconds.
            let reset_at: TimeInterval?
        }

        let allowed: Bool?
        let limit_reached: Bool?
        let primary_window: Window?
        let secondary_window: Window?
    }

    let plan_type: String?
    let rate_limit: RateLimit?
}

extension CodexUsageResponse {
    /// Small tolerance for comparing API double values.
    private static let secondsEqualityTolerance: TimeInterval = 0.001

    func toSnapshot(fetchedAt: Date) -> UsageSnapshot {
        let limitReached = rate_limit?.limit_reached ?? false
        let primary = makeWindow(source: rate_limit?.primary_window, kind: .primary)
        let secondary = makeWindow(source: rate_limit?.secondary_window, kind: .secondary)
        return UsageSnapshot(
            provider: .chatgptCodex,
            fetchedAt: fetchedAt,
            primaryWindow: primary,
            secondaryWindow: secondary,
            planType: plan_type,
            limitReached: limitReached,
            extraUsage: nil
        )
    }

    private func makeWindow(
        source: RateLimit.Window?,
        kind: UsageWindowKind
    ) -> UsageWindow? {
        guard let source,
              let usedPercent = source.used_percent,
              let limitSeconds = source.limit_window_seconds else {
            return nil
        }
        // Skip "freshly reset" windows where 0% used and the entire window
        // duration is still available (matches the prior WebView behavior).
        if usedPercent == 0,
           let resetAfterSeconds = source.reset_after_seconds,
           abs(limitSeconds - resetAfterSeconds) <= Self.secondsEqualityTolerance {
            return nil
        }
        let resetAt = source.reset_at.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            resetAt: resetAt,
            limitWindowSeconds: limitSeconds
        )
    }
}

// MARK: - Codex Usage Fetcher

/// Fetches Codex usage via HTTPS using the CLI-rotated access token.
final class CodexUsageFetcher {
    private let http: NativeUsageHTTPClient

    init(http: NativeUsageHTTPClient = NativeUsageHTTPClient()) {
        self.http = http
    }

    /// Returns true when an access token can be read off disk. The actual
    /// validity is only known by hitting the endpoint, but this is enough
    /// for the UI to decide between "logged in" and "needs codex login".
    func hasValidSession() -> Bool {
        (try? CodexAuthStore.loadAccessToken()) != nil
    }

    /// Fetches the current usage snapshot. Throws `UsageAuthError`.
    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        let token = try CodexAuthStore.loadAccessToken()
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw UsageAuthError.invalidResponse(reason: "invalid usage URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let raw = try await http.send(request)
        switch raw.response.statusCode {
        case 200...299:
            do {
                let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: raw.data)
                return decoded.toSnapshot(fetchedAt: Date())
            } catch {
                throw UsageAuthError.invalidResponse(reason: error.localizedDescription)
            }
        case 401:
            throw UsageAuthError.codexAuthExpired
        case 429:
            throw UsageAuthError.rateLimited
        default:
            throw UsageAuthError.httpStatus(code: raw.response.statusCode, body: raw.bodyString)
        }
    }
}
