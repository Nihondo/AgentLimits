// MARK: - ClaudeUsageFetcher.swift
// Native Claude (Anthropic) usage fetcher. Reuses the user's already-granted
// Claude Code OAuth session via the keychain item written by `claude /login`.
// No WKWebView, no JS injection, no API keys — only the rotated OAuth tokens.
//
// Status-code matrix (per codex-island):
//   200 + body.error.type == "rate_limit_error" → rateLimited
//   200                                          → parse
//   401                                          → refresh once + retry
//   403 (scope insufficient: missing user:profile) → claudeReLogin
//   429                                          → rateLimited
//
// 5-minute minimum poll interval is enforced upstream (UsageViewModel).

import Foundation

// MARK: - API Response Models

/// Response from `GET https://api.anthropic.com/api/oauth/usage`.
struct ClaudeUsageResponse: Codable {
    struct Window: Codable {
        let utilization: Double?
        /// ISO8601 string OR epoch-seconds Double depending on field/account.
        let resets_at: ResetsAt?
    }

    /// Discriminated union for `resets_at` — string OR number.
    enum ResetsAt: Codable {
        case iso(String)
        case epoch(Double)
        case absent

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .absent; return }
            if let s = try? container.decode(String.self) { self = .iso(s); return }
            if let d = try? container.decode(Double.self) { self = .epoch(d); return }
            self = .absent
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .iso(let s): try container.encode(s)
            case .epoch(let d): try container.encode(d)
            case .absent: try container.encodeNil()
            }
        }
    }

    struct ExtraUsage: Codable {
        let is_enabled: Bool?
        let monthly_limit: Double?
        let used_credits: Double?
        let utilization: Double?
        let currency: String?
    }

    /// Anthropic sometimes returns HTTP 200 with this error block instead of 429.
    struct RateLimitErrorBody: Codable {
        let type: String?
        let message: String?
    }

    struct RateLimitErrorWrapper: Codable {
        let error: RateLimitErrorBody?
    }

    let five_hour: Window?
    let seven_day: Window?
    let extra_usage: ExtraUsage?
}

extension ClaudeUsageResponse {
    func toSnapshot(fetchedAt: Date, planType: String?) -> UsageSnapshot {
        let primary = makeWindow(
            source: five_hour,
            kind: .primary,
            limitSeconds: UsageLimitDuration.fiveHours
        )
        let secondary = makeWindow(
            source: seven_day,
            kind: .secondary,
            limitSeconds: UsageLimitDuration.sevenDays
        )
        let extra = extra_usage.map {
            ExtraUsageInfo(
                isEnabled: $0.is_enabled ?? false,
                monthlyLimit: $0.monthly_limit,
                usedCredits: $0.used_credits,
                utilization: $0.utilization,
                currency: $0.currency
            )
        }
        return UsageSnapshot(
            provider: .claudeCode,
            fetchedAt: fetchedAt,
            primaryWindow: primary,
            secondaryWindow: secondary,
            planType: planType,
            limitReached: false,
            extraUsage: extra
        )
    }

    private func makeWindow(
        source: Window?,
        kind: UsageWindowKind,
        limitSeconds: TimeInterval
    ) -> UsageWindow? {
        guard let source, let rawUtilization = source.utilization else { return nil }
        // Codex-island contract: utilization arrives in [0, 100]. Clamp without
        // a "raw > 1 ? raw/100 : raw" heuristic — that heuristic breaks at
        // window reset when utilization legitimately enters (0, 1].
        let usedPercent = max(0, min(100, rawUtilization))
        let resetAt: Date?
        switch source.resets_at {
        case .iso(let s):
            resetAt = ClaudeResetDateParser.parse(s)
        case .epoch(let d):
            resetAt = Date(timeIntervalSince1970: d)
        case .absent, .none:
            // Treat absent reset as "not yet initialized" — drop the window.
            return nil
        }
        guard let resetAt else { return nil }
        return UsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            resetAt: resetAt,
            limitWindowSeconds: limitSeconds
        )
    }
}

// MARK: - ISO8601 Parsing

enum ClaudeResetDateParser {
    private static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let withoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ value: String) -> Date? {
        if let d = withFractional.date(from: value) { return d }
        if let d = withoutFractional.date(from: value) { return d }
        // Normalize >3-digit fractional seconds to milliseconds.
        if let trimmed = trimFractionalSeconds(value),
           let d = withFractional.date(from: trimmed) {
            return d
        }
        return nil
    }

    private static func trimFractionalSeconds(_ value: String) -> String? {
        guard let dotIdx = value.firstIndex(of: ".") else { return nil }
        let fractionStart = value.index(after: dotIdx)
        guard let suffixStart = value[fractionStart...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else {
            return nil
        }
        let fraction = value[fractionStart..<suffixStart]
        if fraction.count <= 3 { return value }
        let trimmedFraction = fraction.prefix(3)
        return String(value[..<fractionStart]) + trimmedFraction + value[suffixStart...]
    }
}

// MARK: - Claude Usage Fetcher

/// Fetches Claude usage by reusing the user's claude /login OAuth session.
final class ClaudeUsageFetcher {
    private let http: NativeUsageHTTPClient
    private let oauthClient: ClaudeOAuthClient

    init(
        http: NativeUsageHTTPClient = NativeUsageHTTPClient(),
        oauthClient: ClaudeOAuthClient = ClaudeOAuthClient()
    ) {
        self.http = http
        self.oauthClient = oauthClient
    }

    /// True when we can locate an access token without hitting the network.
    /// Used by the UI to choose between "logged in" and "needs claude /login".
    func hasValidSession() -> Bool {
        if ProcessInfo.processInfo.environment[ClaudeOAuthConfig.envTokenVariable]?.isEmpty == false {
            return true
        }
        return (try? ClaudeKeychainStore.loadCredentials()) != nil
    }

    /// Fetches the current usage snapshot. Throws `UsageAuthError`.
    /// On 401, refreshes the OAuth tokens via the keychain refresh_token,
    /// writes the rotated pair back, and retries the GET once.
    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        let initial = try resolveAccessTokenAndPlan()
        let accessToken = initial.accessToken
        var planType = initial.planType
        let raw = try await performUsageGET(accessToken: accessToken)
        switch raw.response.statusCode {
        case 200...299:
            if let wrapper = try? JSONDecoder().decode(ClaudeUsageResponse.RateLimitErrorWrapper.self, from: raw.data),
               wrapper.error?.type == "rate_limit_error" {
                throw UsageAuthError.rateLimited
            }
            do {
                let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: raw.data)
                return decoded.toSnapshot(fetchedAt: Date(), planType: planType)
            } catch {
                throw UsageAuthError.invalidResponse(reason: error.localizedDescription)
            }
        case 401:
            // Refresh once + retry. Refresh re-issues with the SAME scope, so
            // 403 (scope insufficient) cannot be helped by refresh and we
            // surface .claudeReLogin instead (handled in the 403 branch below).
            let newAccess: String
            do {
                newAccess = try await oauthClient.refreshAndPersist()
            } catch let refreshError as UsageAuthError {
                throw refreshError
            }
            planType = (try? ClaudeKeychainStore.loadCredentials().payload.claudeAiOauth.subscriptionType) ?? planType
            let retry = try await performUsageGET(accessToken: newAccess)
            switch retry.response.statusCode {
            case 200...299:
                if let wrapper = try? JSONDecoder().decode(ClaudeUsageResponse.RateLimitErrorWrapper.self, from: retry.data),
                   wrapper.error?.type == "rate_limit_error" {
                    throw UsageAuthError.rateLimited
                }
                do {
                    let decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: retry.data)
                    return decoded.toSnapshot(fetchedAt: Date(), planType: planType)
                } catch {
                    throw UsageAuthError.invalidResponse(reason: error.localizedDescription)
                }
            case 401:
                throw UsageAuthError.claudeAuthExpired
            case 403:
                throw UsageAuthError.claudeReLogin
            case 429:
                throw UsageAuthError.rateLimited
            default:
                throw UsageAuthError.httpStatus(code: retry.response.statusCode, body: retry.bodyString)
            }
        case 403:
            throw UsageAuthError.claudeReLogin
        case 429:
            throw UsageAuthError.rateLimited
        default:
            throw UsageAuthError.httpStatus(code: raw.response.statusCode, body: raw.bodyString)
        }
    }

    // MARK: - Helpers

    private struct InitialResolution {
        let accessToken: String
        let planType: String?
    }

    /// Token resolution order, per codex-island:
    /// 1. CLAUDE_CODE_OAUTH_TOKEN env var (Claude Desktop child processes)
    /// 2. Keychain payload's accessToken
    /// 3. Refresh handled later in the 401 branch (not pre-emptively here)
    private func resolveAccessTokenAndPlan() throws -> InitialResolution {
        if let env = ProcessInfo.processInfo.environment[ClaudeOAuthConfig.envTokenVariable],
           !env.isEmpty {
            let plan = (try? ClaudeKeychainStore.loadCredentials().payload.claudeAiOauth.subscriptionType)
            return InitialResolution(accessToken: env, planType: plan)
        }
        let (payload, _) = try ClaudeKeychainStore.loadCredentials()
        return InitialResolution(
            accessToken: payload.claudeAiOauth.accessToken,
            planType: payload.claudeAiOauth.subscriptionType
        )
    }

    private func performUsageGET(accessToken: String) async throws -> NativeUsageHTTPClient.RawResponse {
        var request = URLRequest(url: ClaudeOAuthConfig.usageEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(ClaudeOAuthConfig.oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(ClaudeOAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await http.send(request)
    }
}
