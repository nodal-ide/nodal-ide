//
//  CodeEditAnimations.swift
//  CodeEdit
//
//  Shared animation constants so panel/structural animations feel consistent.
//

import SwiftUI

enum CodeEditAnimations {
    /// Duration for panel show/hide (navigator, inspector, utility area) and other structural moves.
    static let panelCollapseDuration: TimeInterval = 0.25

    /// The matching SwiftUI animation for panel show/hide.
    static let panelCollapse: Animation = .easeInOut(duration: panelCollapseDuration)

    /// A quick animation for small, local UI changes (hover, inline reveals).
    static let quick: Animation = .easeInOut(duration: 0.12)
}
