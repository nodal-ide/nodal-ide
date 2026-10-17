//
//  Metrics.swift
//  CodeEdit
//
//  Shared layout metrics (design tokens) so panel geometry has a single source of truth.
//  Adopt these in new/touched code; existing magic numbers should migrate over time.
//

import CoreGraphics

enum Metrics {
    /// Sidebar / navigator / inspector geometry.
    enum Sidebar {
        static let minWidth: CGFloat = 242
        static let snapWidth: CGFloat = 272
        static let maxSnapWidth: CGFloat = snapWidth + 10
        static let minSnapWidth: CGFloat = snapWidth - 10
        /// Drag distance below which a pane collapses.
        static let collapseThreshold: CGFloat = 121
        /// Extra hit area (points) around a split divider.
        static let dividerGrab: CGFloat = 5
    }

    /// Bar / toolbar heights.
    enum Bar {
        static let tabBarHeight: CGFloat = 28
        static let jumpBarHeight: CGFloat = 28
        static let statusBarHeight: CGFloat = {
            if #available(macOS 26, *) { 37 } else { 29 }
        }()
    }

    /// Corner radii.
    enum CornerRadius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 6
        static let large: CGFloat = 8
    }

    /// Common spacing values.
    enum Spacing {
        static let tight: CGFloat = 4
        static let regular: CGFloat = 8
        static let loose: CGFloat = 12
    }
}
