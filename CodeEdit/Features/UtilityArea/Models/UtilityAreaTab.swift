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
    case console
    case debug

    var title: String {
        switch self {
        case .terminal:
            return "Terminal"
        case .console:
            return "Console"
        case .debug:
            return "Debug"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal:
            return "terminal"
        case .console:
            return "list.bullet.rectangle"
        case .debug:
            return "ladybug.fill"
        }
    }

    var body: some View {
        switch self {
        case .terminal:
            UtilityAreaTerminalView()
        case .console:
            UtilityAreaOutputView()
        case .debug:
            DebugSessionView()
        }
    }
}
