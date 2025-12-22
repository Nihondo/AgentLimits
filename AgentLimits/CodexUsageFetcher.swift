// MARK: - CodexUsageFetcher.swift
// Fetches usage data from ChatGPT Codex via JavaScript injection.
// Uses access token from session API to authenticate usage endpoint.

import Foundation
import WebKit

// MARK: - API Response Models

/// Response structure from ChatGPT Codex usage API
struct CodexUsageResponse: Codable {
    struct RateLimit: Codable {
        struct Window: Codable {
            let used_percent: Double?
            let limit_window_seconds: Double?
            let reset_at: TimeInterval?
        }

        let primary_window: Window?
        let secondary_window: Window?
    }

    let plan_type: String?
    let rate_limit: RateLimit?
}

extension CodexUsageResponse {
    func toSnapshot(fetchedAt: Date) -> UsageSnapshot {
        let primary: UsageWindow?
        if let window = rate_limit?.primary_window,
           let usedPercent = window.used_percent,
           let limitSeconds = window.limit_window_seconds {
            let resetAt = window.reset_at.map { Date(timeIntervalSince1970: $0) }
            primary = UsageWindow(
                kind: .primary,
                usedPercent: usedPercent,
                resetAt: resetAt,
                limitWindowSeconds: limitSeconds
            )
        } else {
            primary = nil
        }

        let secondary: UsageWindow?
        if let window = rate_limit?.secondary_window,
           let usedPercent = window.used_percent,
           let limitSeconds = window.limit_window_seconds {
            let resetAt = window.reset_at.map { Date(timeIntervalSince1970: $0) }
            secondary = UsageWindow(
                kind: .secondary,
                usedPercent: usedPercent,
                resetAt: resetAt,
                limitWindowSeconds: limitSeconds
            )
        } else {
            secondary = nil
        }

        return UsageSnapshot(
            provider: .chatgptCodex,
            fetchedAt: fetchedAt,
            primaryWindow: primary,
            secondaryWindow: secondary
        )
    }
}

// MARK: - Error Types

/// Errors that can occur when fetching Codex usage data
enum CodexUsageFetcherError: LocalizedError {
    case pageNotReady
    case scriptFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .pageNotReady:
            return "error.loginNotLoaded".localized()
        case .scriptFailed(let message):
            return "error.fetchFailed".localized(message)
        case .invalidResponse:
            return "error.parseFailed".localized()
        }
    }
}

// MARK: - Codex Usage Fetcher

/// Fetches usage data from ChatGPT Codex by executing JavaScript in WebView.
/// Authenticates via session API to get access token for usage endpoint.
final class CodexUsageFetcher {
    private let scriptRunner: WebViewScriptRunner

    init(scriptRunner: WebViewScriptRunner = WebViewScriptRunner()) {
        self.scriptRunner = scriptRunner
    }

    /// Fetches current usage snapshot by executing JavaScript in the WebView
    @MainActor
    func fetchUsageSnapshot(using webView: WKWebView) async throws -> UsageSnapshot {
        let response: CodexUsageResponse
        do {
            response = try await scriptRunner.decodeJSONScript(
                CodexUsageResponse.self,
                script: Self.usageScript,
                webView: webView
            )
        } catch let error as WebViewScriptRunnerError {
            throw mapScriptError(error)
        }
        return response.toSnapshot(fetchedAt: Date())
    }

    /// Checks if user is logged in by verifying access token exists
    @MainActor
    func hasValidSession(using webView: WKWebView) async -> Bool {
        do {
            return try await scriptRunner.runBooleanScript(Self.loginCheckScript, webView: webView)
        } catch {
            return false
        }
    }

    private func mapScriptError(_ error: WebViewScriptRunnerError) -> CodexUsageFetcherError {
        switch error {
        case .invalidResponse:
            return .invalidResponse
        case .scriptFailed(let message):
            return .scriptFailed(message)
        }
    }

    // MARK: - JavaScript Scripts

    /// Script to fetch usage data: gets session token, then calls usage API
    private static let usageScript = """
    return (async () => {
      try {
        async function fetchSession() {
          let response = await fetch("/api/auth/session", { credentials: "include" });
          if (response.ok) {
            return await response.json();
          }
          response = await fetch("/backend-api/auth/session", { credentials: "include" });
          if (response.ok) {
            return await response.json();
          }
          return null;
        }

        const session = await fetchSession();
        const accessToken = session && (session.accessToken || session.access_token);
        if (!accessToken) {
          throw new Error("Missing access token");
        }

        const response = await fetch("https://chatgpt.com/backend-api/wham/usage", {
          method: "GET",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Authorization": "Bearer " + accessToken
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

    /// Script to check login status by verifying access token exists
    private static let loginCheckScript = """
    return (async () => {
      try {
        async function fetchSession() {
          let response = await fetch("/api/auth/session", { credentials: "include" });
          if (response.ok) {
            return await response.json();
          }
          response = await fetch("/backend-api/auth/session", { credentials: "include" });
          if (response.ok) {
            return await response.json();
          }
          return null;
        }

        const session = await fetchSession();
        const accessToken = session && (session.accessToken || session.access_token);
        return !!accessToken;
      } catch (error) {
        return false;
      }
    })();
    """
}
