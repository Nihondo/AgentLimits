// MARK: - HeatmapView.swift
// Heatmap grid view displaying one month of daily usage.
// Layout follows GitHub contributions graph pattern.

import SwiftUI
import WidgetKit

// MARK: - Heatmap View

/// Heatmap grid view displaying one month of daily token usage.
/// Layout: 7 rows (Sun-Sat) × 5-6 columns (weeks).
/// Weekday labels (Mon, Wed, Fri) are displayed on the left side.
struct HeatmapView: View {
    let dailyUsage: [DailyUsageEntry]
    let currentDate: Date
    /// Cell size for each day (configurable for different widget sizes)
    var cellSize: CGFloat = 10

    /// Widget rendering mode for adapting colors to desktop pinned widgets
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Spacing between cells
    private var cellSpacing: CGFloat { cellSize * 0.2 }
    /// Corner radius for rounded rectangles
    private var cornerRadius: CGFloat { cellSize * 0.2 }
    /// Width for weekday labels
    private var labelWidth: CGFloat { cellSize * 2.5 }

    /// Number of rows (days of week: Sun=0, Sat=6)
    private let rows = 7

    /// Weekday labels to display (only Mon, Wed, Fri)
    private let weekdayLabels: [Int: String] = [
        1: "Mon",
        3: "Wed",
        5: "Fri"
    ]

    var body: some View {
        let levels = HeatmapLevelResolver.calculateLevels(from: dailyUsage)
        let grid = buildMonthGrid()

        HStack(alignment: .top, spacing: 2) {
            // Weekday labels column
            VStack(alignment: .trailing, spacing: cellSpacing) {
                ForEach(0..<rows, id: \.self) { row in
                    if let label = weekdayLabels[row] {
                        Text(label)
                            .font(.system(size: cellSize * 0.8))
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, height: cellSize, alignment: .trailing)
                    } else {
                        Color.clear
                            .frame(width: labelWidth, height: cellSize)
                    }
                }
            }

            // Heatmap grid
            HStack(spacing: cellSpacing) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<rows, id: \.self) { row in
                            if let dateString = grid[row][safe: column] ?? nil {
                                let level = levels[dateString] ?? .none
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(level.color(for: renderingMode))
                                    .frame(width: cellSize, height: cellSize)
                            } else {
                                // Empty cell for alignment
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(Color.clear)
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grid Calculation

    /// Number of columns needed for the month (5-6 weeks)
    private var columns: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: currentDate)
        guard let startOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return 6
        }
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let totalCells = (firstWeekday - 1) + range.count
        return Int(ceil(Double(totalCells) / 7.0))
    }

    /// Builds the grid layout for the current month.
    /// Returns [row][column] where row is weekday (0=Sun, 6=Sat).
    private func buildMonthGrid() -> [[String?]] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: currentDate)
        guard let startOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return Array(repeating: Array(repeating: nil, count: columns), count: rows)
        }

        var grid: [[String?]] = Array(repeating: Array(repeating: nil, count: columns), count: rows)

        for day in range {
            guard let date = calendar.date(bySetting: .day, value: day, of: startOfMonth) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: date) - 1 // 0-indexed (Sun=0)
            let weekOfMonth = calendar.component(.weekOfMonth, from: date) - 1
            let dateString = String(
                format: "%04d-%02d-%02d",
                calendar.component(.year, from: date),
                calendar.component(.month, from: date),
                day
            )
            grid[weekday][weekOfMonth] = dateString
        }

        return grid
    }
}

// MARK: - Array Extension

extension Array {
    /// Safe subscript that returns nil for out-of-bounds indices.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview {
    HeatmapView(
        dailyUsage: (1...31).map { day in
            DailyUsageEntry(
                date: String(format: "2025-12-%02d", day),
                totalTokens: [0, 100000, 500000, 1000000, 2000000].randomElement() ?? 0
            )
        },
        currentDate: Date()
    )
    .padding()
}
