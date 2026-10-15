//
//  UtilityAreaTab.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 02/06/2023.
//

import SwiftUI

enum UtilityAreaTab: WorkspacePanelTab, CaseIterable {
    var id: Self { self }

    case problems
    case terminal
    case debugConsole
    case output
    case tests

    var title: String {
        switch self {
        case .problems:
            return "Problems"
        case .terminal:
            return "Terminal"
        case .debugConsole:
            return "Debug Console"
        case .output:
            return "Output"
        case .tests:
            return "Tests"
        }
    }

    var systemImage: String {
        switch self {
        case .problems:
            return "exclamationmark.triangle"
        case .terminal:
            return "terminal"
        case .debugConsole:
            return "ladybug"
        case .output:
            return "list.bullet.indent"
        case .tests:
            return "checkmark.diamond"
        }
    }

    var body: some View {
        switch self {
        case .problems:
            ProblemsView()
        case .terminal:
            UtilityAreaTerminalView()
        case .debugConsole:
            UtilityAreaDebugView()
        case .output:
            UtilityAreaOutputView()
        case .tests:
            TestsView()
        }
    }
}