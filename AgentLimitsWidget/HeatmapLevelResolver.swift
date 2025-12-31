// MARK: - HeatmapLevelResolver.swift
// Quartile-based level calculation for heatmap visualization.

import Foundation

// MARK: - Heatmap Level Resolver

/// Resolves heatmap levels from daily usage data using quartile calculation.
enum HeatmapLevelResolver {
    /// Calculates heatmap levels for each day based on quartile distribution.
    /// - Parameter dailyUsage: Array of daily usage entries with ISO8601 dates
    /// - Returns: Dictionary mapping date strings to HeatmapLevel
    static func calculateLevels(from dailyUsage: [DailyUsageEntry]) -> [String: HeatmapLevel] {
        // Filter out zero-usage days for quartile calculation
        let nonZeroTokens = dailyUsage
            .map { $0.totalTokens }
            .filter { $0 > 0 }
            .sorted()

        guard !nonZeroTokens.isEmpty else {
            // All days have zero usage
            return Dictionary(
                uniqueKeysWithValues: dailyUsage.map { ($0.date, HeatmapLevel.none) }
            )
        }

        // Calculate quartile thresholds
        let q1 = percentile(nonZeroTokens, at: 0.25)
        let q2 = percentile(nonZeroTokens, at: 0.50)
        let q3 = percentile(nonZeroTokens, at: 0.75)

        // Map each day to its level
        return Dictionary(uniqueKeysWithValues: dailyUsage.map { entry in
            let level = levelForTokens(entry.totalTokens, q1: q1, q2: q2, q3: q3)
            return (entry.date, level)
        })
    }

    /// Calculates the value at a given percentile in a sorted array.
    /// - Parameters:
    ///   - sorted: Sorted array of integers
    ///   - p: Percentile (0.0 to 1.0)
    /// - Returns: Value at the specified percentile
    private static func percentile(_ sorted: [Int], at p: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
    }

    /// Determines the heatmap level for a given token count.
    /// - Parameters:
    ///   - tokens: Token count for the day
    ///   - q1: First quartile threshold
    ///   - q2: Second quartile threshold (median)
    ///   - q3: Third quartile threshold
    /// - Returns: Appropriate HeatmapLevel based on quartile position
    private static func levelForTokens(
        _ tokens: Int,
        q1: Int,
        q2: Int,
        q3: Int
    ) -> HeatmapLevel {
        if tokens == 0 { return .none }
        if tokens <= q1 { return .firstQuartile }
        if tokens <= q2 { return .secondQuartile }
        if tokens <= q3 { return .thirdQuartile }
        return .fourthQuartile
    }
}
