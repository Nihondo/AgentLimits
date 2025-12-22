// MARK: - WebViewScriptRunner.swift
// Small helper that runs JavaScript in WKWebView and decodes JSON responses.
// Normalizes script errors so callers can present localized messages.

import Foundation
import WebKit

/// Errors that can occur when executing scripts inside WKWebView
enum WebViewScriptRunnerError: LocalizedError {
    case invalidResponse
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "error.parseFailed".localized()
        case .scriptFailed(let message):
            return "error.fetchFailed".localized(message)
        }
    }
}

/// Utility for evaluating JavaScript and decoding returned JSON strings
struct WebViewScriptRunner {
    /// Runs a script expected to return a JSON string; throws if missing/invalid
    @MainActor
    func runJSONScript(_ script: String, webView: WKWebView) async throws -> String {
        let result = try await evaluateJavaScript(script, webView: webView)
        guard let jsonString = result as? String else {
            throw WebViewScriptRunnerError.invalidResponse
        }
        if let errorMessage = extractErrorMessage(from: jsonString) {
            throw WebViewScriptRunnerError.scriptFailed(errorMessage)
        }
        return jsonString
    }

    /// Runs a script and decodes the resulting JSON string into Decodable type
    @MainActor
    func decodeJSONScript<T: Decodable>(
        _ type: T.Type,
        script: String,
        webView: WKWebView,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let jsonString = try await runJSONScript(script, webView: webView)
        let data = Data(jsonString.utf8)
        return try decoder.decode(T.self, from: data)
    }

    /// Runs a script expected to return a boolean value
    @MainActor
    func runBooleanScript(_ script: String, webView: WKWebView) async throws -> Bool {
        let result = try await evaluateJavaScript(script, webView: webView)
        guard let value = result as? Bool else {
            throw WebViewScriptRunnerError.invalidResponse
        }
        return value
    }

    @MainActor
    private func evaluateJavaScript(_ script: String, webView: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: WebViewScriptRunnerError.scriptFailed(error.localizedDescription))
                }
            }
        }
    }

    /// If the JSON payload encodes an __error key, extract it for surfaceable errors
    private func extractErrorMessage(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return jsonObject["__error"] as? String
    }
}
