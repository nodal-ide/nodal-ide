//
//  CodeEditAnimations.swift
//  CodeEdit
//
//  Shared animation constants so panel/structural animations feel consistent.
//

import SwiftUI
import QuartzCore

enum CodeEditAnimations {
    /// Duration for panel show/hide (navigator, inspector, utility area) and other structural moves.
    static let panelCollapseDuration: TimeInterval = 0.28

    /// The matching SwiftUI animation for panel show/hide.
    static let panelCollapse: Animation = .easeInOut(duration: panelCollapseDuration)

    /// The matching AppKit timing function for panel show/hide.
    static var panelCollapseTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeInEaseOut)
    }

    /// A quick animation for small, local UI changes (hover, inline reveals).
    static let quick: Animation = .easeInOut(duration: 0.12)
}
