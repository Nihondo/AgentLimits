// MARK: - ClaudeUsageFetcher.swift
// Fetches usage data from Claude.ai via JavaScript injection.
// Extracts organization ID from cookies or page content to call usage API.

import Foundation
import WebKit

// MARK: - API Response Models

/// Response structure from Claude.ai usage API
struct ClaudeUsageResponse: Codable {
    struct Window: Codable {
        let utilization: Double?
        let resets_at: String?
    }

    let five_hour: Window?
    let seven_day: Window?
    let seven_day_oauth_apps: Window?
    let seven_day_opus: Window?
    let seven_day_sonnet: Window?
    let iguana_necktie: Window?
    let extra_usage: Window?
}

extension ClaudeUsageResponse {
    func toSnapshot(fetchedAt: Date, parseResetDate: (String) -> Date?) -> UsageSnapshot {
        let primary = makeWindow(
            kind: .primary,
            source: five_hour,
            limitSeconds: 60 * 60 * 5,
            parseResetDate: parseResetDate
        )
        let secondary = makeWindow(
            kind: .secondary,
            source: seven_day,
            limitSeconds: 60 * 60 * 24 * 7,
            parseResetDate: parseResetDate
        )
        return UsageSnapshot(
            provider: .claudeCode,
            fetchedAt: fetchedAt,
            primaryWindow: primary,
            secondaryWindow: secondary
        )
    }

    private func makeWindow(
        kind: UsageWindowKind,
        source: Window?,
        limitSeconds: TimeInterval,
        parseResetDate: (String) -> Date?
    ) -> UsageWindow? {
        guard let source, let usedPercent = source.utilization else {
            return nil
        }
        let resetAt = source.resets_at.flatMap(parseResetDate)
        return UsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            resetAt: resetAt,
            limitWindowSeconds: limitSeconds
        )
    }
}

// MARK: - Error Types

/// Errors that can occur when fetching Claude usage data
enum ClaudeUsageFetcherError: LocalizedError {
    case scriptFailed(String)
    case invalidResponse
    case missingOrganization

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message):
            return "error.fetchFailed".localized(message)
        case .invalidResponse:
            return "error.parseFailed".localized()
        case .missingOrganization:
            return "error.missingOrg".localized()
        }
    }
}

// MARK: - Claude Usage Fetcher

/// Fetches usage data from Claude.ai by executing JavaScript in WebView.
/// Obtains organization ID from cookies or page content to authenticate.
final class ClaudeUsageFetcher {
    private let scriptRunner: WebViewScriptRunner

    init(scriptRunner: WebViewScriptRunner = WebViewScriptRunner()) {
        self.scriptRunner = scriptRunner
    }

    /// Fetches current usage snapshot by executing JavaScript in the WebView
    @MainActor
    func fetchUsageSnapshot(using webView: WKWebView) async throws -> UsageSnapshot {
        let response: ClaudeUsageResponse
        do {
            response = try await scriptRunner.decodeJSONScript(
                ClaudeUsageResponse.self,
                script: Self.usageScript,
                webView: webView
            )
        } catch let error as WebViewScriptRunnerError {
            throw mapScriptError(error)
        } catch {
            throw ClaudeUsageFetcherError.invalidResponse
        }
        return response.toSnapshot(fetchedAt: Date(), parseResetDate: parseResetDate)
    }

    /// Checks if user is logged in by verifying organization cookie or API
    @MainActor
    func hasValidSession(using webView: WKWebView) async -> Bool {
        do {
            return try await scriptRunner.runBooleanScript(Self.loginCheckScript, webView: webView)
        } catch {
            return false
        }
    }

    private func mapScriptError(_ error: WebViewScriptRunnerError) -> ClaudeUsageFetcherError {
        switch error {
        case .invalidResponse:
            return .invalidResponse
        case .scriptFailed(let message):
            if message.contains("Missing organization id") {
                return .missingOrganization
            }
            return .scriptFailed(message)
        }
    }

    // MARK: - Date Parsing

    /// Parses ISO8601 date string with various fractional second formats
    private func parseResetDate(_ value: String) -> Date? {
        if let date = Self.formatterWithFractionalSeconds.date(from: value) {
            return date
        }
        if let date = Self.formatterWithoutFractionalSeconds.date(from: value) {
            return date
        }
        if let trimmed = trimFractionalSeconds(value),
           let date = Self.formatterWithFractionalSeconds.date(from: trimmed) {
            return date
        }
        return nil
    }

    private func trimFractionalSeconds(_ value: String) -> String? {
        guard let dotIndex = value.firstIndex(of: ".") else { return nil }
        let fractionStart = value.index(after: dotIndex)
        guard let suffixStart = value[fractionStart...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else {
            return nil
        }
        let fraction = value[fractionStart..<suffixStart]
        if fraction.count <= 3 {
            return value
        }
        let trimmedFraction = fraction.prefix(3)
        return String(value[..<fractionStart]) + trimmedFraction + value[suffixStart...]
    }

    private static let formatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let formatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - JavaScript Scripts

    /// Script to fetch usage: finds org ID from cookie/resources/HTML, then calls API
    private static let usageScript = """
    return (async () => {
      try {
        function readCookieValue(name) {
          const pattern = new RegExp("(?:^|; )" + name + "=([^;]*)");
          const match = document.cookie.match(pattern);
          return match ? decodeURIComponent(match[1]) : null;
        }

        function findOrgIdFromResources() {
          const entries = performance.getEntriesByType("resource");
          for (const entry of entries) {
            if (!entry || !entry.name) { continue; }
            const match = entry.name.match(/\\/api\\/organizations\\/([a-f0-9-]{36})\\/usage/);
            if (match) { return match[1]; }
          }
          return null;
        }

        function findOrgIdFromHtml() {
          const html = document.documentElement ? document.documentElement.innerHTML : "";
          const match = html.match(/\\/api\\/organizations\\/([a-f0-9-]{36})\\/usage/);
          return match ? match[1] : null;
        }

        const orgId = readCookieValue("lastActiveOrg")
          || findOrgIdFromResources()
          || findOrgIdFromHtml();
        if (!orgId) {
          throw new Error("Missing organization id");
        }

        const response = await fetch("https://claude.ai/api/organizations/" + orgId + "/usage", {
          method: "GET",
          credentials: "include",
          headers: {
            "Accept": "application/json"
          }
        });
        if (!response.ok) {
          throw new Error("HTTP " + response.status);
        }
        const data = await response.json();
        return JSON.stringify(data);
      } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return JSON.stringify({ "__error": message });
      }
    })();
    """

    /// Script to check login status via organization cookie or API call
    private static let loginCheckScript = """
    return (async () => {
      try {
        function readCookieValue(name) {
          const pattern = new RegExp("(?:^|; )" + name + "=([^;]*)");
          const match = document.cookie.match(pattern);
          return match ? decodeURIComponent(match[1]) : null;
        }

        const orgId = readCookieValue("lastActiveOrg");
        if (orgId) {
          return true;
        }

        const response = await fetch("/api/organizations", {
          method: "GET",
          credentials: "include"
        });
        if (!response.ok) {
          return false;
        }
        const data = await response.json();
        if (data && Array.isArray(data.organizations)) {
          return data.organizations.length > 0;
        }
        return true;
      } catch (error) {
        return false;
      }
    })();
    """
}
