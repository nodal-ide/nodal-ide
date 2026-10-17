//
//  UtilityAreaTab.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 02/06/2023.
//

import SwiftUI

enum UtilityAreaTab: WorkspacePanelTab, CaseIterable {
    var id: Self { self }

    case terminal
    case debugConsole
    case output
    case tests
    case debug

    var title: String {
        switch self {
        case .terminal:
            return "Terminal"
        case .debugConsole:
            return "Debug Console"
        case .output:
            return "Output"
        case .tests:
            return "Tests"
        case .debug:
            return "Debug"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal:
            return "terminal"
        case .debugConsole:
            return "ladybug"
        case .output:
            return "list.bullet.indent"
        case .tests:
            return "checkmark.diamond"
        case .debug:
            return "ladybug.fill"
        }
    }

    var body: some View {
        switch self {
        case .terminal:
            UtilityAreaTerminalView()
        case .debugConsole:
            UtilityAreaDebugView()
        case .output:
            UtilityAreaOutputView()
        case .tests:
            TestsView()
        case .debug:
            DebugSessionView()
        }
    }
}
