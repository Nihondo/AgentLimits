// MARK: - DesignTokens.swift
// Shared design tokens for settings UI.

import CoreGraphics

/// Shared design tokens for layout and sizing.
enum DesignTokens {
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let sectionGap: CGFloat = 20
    }

    enum CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
    }

    enum WindowSize {
        static let minWidth: CGFloat = 550
        static let minHeight: CGFloat = 500
    }
}
