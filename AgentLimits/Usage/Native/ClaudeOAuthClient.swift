// MARK: - ClaudeOAuthClient.swift
// Performs the Anthropic OAuth refresh flow and writes the rotated token
// pair back into the `Claude Code-credentials` keychain item.
//
// CRITICAL: Both access_token AND refresh_token rotate on every refresh.
// The new pair MUST be written back to the keychain atomically or Claude
// Code itself will 401 on its next refresh.

import Foundation

/// Executes the OAuth refresh flow against `platform.claude.com/v1/oauth/token`.
struct ClaudeOAuthClient {
    private let http: NativeUsageHTTPClient

    init(http: NativeUsageHTTPClient = NativeUsageHTTPClient()) {
        self.http = http
    }

    /// Refreshes the current credentials and writes the rotated pair back
    /// to the keychain. Returns the new access token for immediate use.
    /// Caller must already have determined that a refresh is needed
    /// (the prior request returned 401, or the cached `expiresAt` is past).
    func refreshAndPersist() async throws -> String {
        let (existing, account) = try ClaudeKeychainStore.loadCredentials()
        let refreshed = try await performRefresh(refreshToken: existing.claudeAiOauth.refreshToken)
        let updatedPayload = ClaudeCredentialsPayload(
            claudeAiOauth: .init(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: refreshed.expiresAtMillis,
                // Preserve everything else.
                subscriptionType: existing.claudeAiOauth.subscriptionType,
                scopes: existing.claudeAiOauth.scopes
            )
        )
        try ClaudeKeychainStore.writeCredentials(updatedPayload, account: account)
        return refreshed.accessToken
    }

    // MARK: - Refresh transport

    private struct RefreshRequestBody: Encodable {
        let grant_type: String
        let refresh_token: String
        let client_id: String
    }

    private struct RefreshResponseBody: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int   // seconds
    }

    /// Rotated tuple returned to the caller.
    struct RefreshedTokens {
        let accessToken: String
        let refreshToken: String
        /// ms-since-epoch.
        let expiresAtMillis: Int64
    }

    private func performRefresh(refreshToken: String) async throws -> RefreshedTokens {
        var request = URLRequest(url: ClaudeOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ClaudeOAuthConfig.userAgent, forHTTPHeaderField: "User-Agent")
        let body = RefreshRequestBody(
            grant_type: "refresh_token",
            refresh_token: refreshToken,
            client_id: ClaudeOAuthConfig.clientID
        )
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw UsageAuthError.invalidResponse(reason: "encode refresh body: \(error.localizedDescription)")
        }
        let raw = try await http.send(request)
        guard (200...299).contains(raw.response.statusCode) else {
            // 4xx on refresh means the refresh token is dead — user must re-login.
            if raw.response.statusCode == 401 || raw.response.statusCode == 400 {
                throw UsageAuthError.claudeAuthExpired
            }
            throw UsageAuthError.httpStatus(code: raw.response.statusCode, body: raw.bodyString)
        }
        let decoded: RefreshResponseBody
        do {
            decoded = try JSONDecoder().decode(RefreshResponseBody.self, from: raw.data)
        } catch {
            throw UsageAuthError.invalidResponse(reason: "decode refresh response: \(error.localizedDescription)")
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let expiresAtMs = nowMs + Int64(decoded.expires_in) * 1000
        return RefreshedTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAtMillis: expiresAtMs
        )
    }
}
