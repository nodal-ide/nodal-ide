//
//  WorkspaceSettingsPage.swift
//  CodeEdit
//
//  Sidebar pages for the Project (Workspace) Settings window.
//

import SwiftUI

enum WorkspaceSettingsPage: String, CaseIterable, Identifiable {
    case general
    case tasks
    case runConfigurations
    case runtimes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .tasks: return "Tasks"
        case .runConfigurations: return "Run & Debug"
        case .runtimes: return "Runtimes"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .tasks: return "hammer"
        case .runConfigurations: return "play.circle"
        case .runtimes: return "shippingbox"
        }
    }

    var baseColor: Color {
        switch self {
        case .general: return .gray
        case .tasks: return .orange
        case .runConfigurations: return .green
        case .runtimes: return .purple
        }
    }
}
