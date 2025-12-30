import Foundation

/// Formats cost and token counts for ccusage output.
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
}
