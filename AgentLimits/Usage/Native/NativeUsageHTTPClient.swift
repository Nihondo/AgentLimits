// MARK: - NativeUsageHTTPClient.swift
// Thin URLSession wrapper used by the native Codex/Claude usage fetchers.
// Returns the raw HTTPURLResponse alongside the body so callers can branch
// on status (401 vs 403 vs 429) — codex-island's status-code matrix relies on
// distinguishing these.

import Foundation

/// One-shot HTTP transport for the native usage fetchers.
/// Intentionally lightweight: no retries (callers own retry semantics, see
/// Claude refresh flow), no auth (callers attach headers explicitly).
struct NativeUsageHTTPClient {
    /// Pair of raw response bytes and the HTTPURLResponse so callers can
    /// status-branch without re-parsing.
    struct RawResponse {
        let data: Data
        let response: HTTPURLResponse

        /// UTF-8 body string (best effort, for error reporting).
        var bodyString: String {
            String(data: data, encoding: .utf8) ?? ""
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Executes an HTTP request and returns the raw response pair.
    /// Throws `UsageAuthError.transport` for transport-layer failures
    /// (DNS, TLS, timeout). Status codes are propagated to the caller.
    func send(_ request: URLRequest) async throws -> RawResponse {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw UsageAuthError.transport(underlying: error)
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw UsageAuthError.invalidResponse(reason: "non-HTTP response")
        }
        return RawResponse(data: result.0, response: http)
    }
}
