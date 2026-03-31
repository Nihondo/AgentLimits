import Foundation

/// Formats cost, token counts, and request counts for usage output.
enum TokenUsageFormatter {
    /// Returns a cost string formatted in USD.
    static func formatCost(_ cost: Double) -> String {
        String(format: "$ %.2f", cost)
    }

    /// Returns a compact token count string in K/M units.
    static func formatTokens(_ tokens: Int) -> String {
        let kTokens = Double(tokens) / 1000.0
        if kTokens >= 1000 {
            return String(format: "%.1fM Tokens", kTokens / 1000.0)
        }
        if kTokens >= 1 {
            return String(format: "%.0fK Tokens", kTokens)
        }
        return "\(tokens) Tokens"
    }

    /// Returns a compact request count string in K/M units.
    static func formatRequests(_ requests: Int) -> String {
        let kRequests = Double(requests) / 1000.0
        if kRequests >= 1000 {
            return String(format: "%.1fK Requests", kRequests / 1000.0)
        }
        if kRequests >= 1 {
            return String(format: "%.0fK Requests", kRequests)
        }
        return "\(requests) Requests"
    }
}
