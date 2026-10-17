//
//  NavigatorTab.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 02/06/2023.
//

import SwiftUI
import CodeEditKit
import ExtensionFoundation

enum NavigatorTab: WorkspacePanelTab {
    case project
    case sourceControl
    case search
    case problems
    case breakpoints
    case uiExtension(endpoint: AppExtensionIdentity, data: ResolvedSidebar.SidebarStore)

    var systemImage: String {
        switch self {
        case .project:
            return "folder"
        case .sourceControl:
            return "vault"
        case .search:
            return "magnifyingglass"
        case .problems:
            return "exclamationmark.triangle"
        case .breakpoints:
            return "circle.fill"
        case .uiExtension(_, let data):
            return data.icon ?? "e.square"
        }
    }

    var id: String {
        if case .uiExtension(let endpoint, let data) = self {
            return endpoint.bundleIdentifier + data.sceneID
        }
        return title
    }

    var title: String {
        switch self {
        case .project:
            return "Project"
        case .sourceControl:
            return "Source Control"
        case .search:
            return "Search"
        case .problems:
            return "Problems"
        case .breakpoints:
            return "Breakpoints"
        case .uiExtension(_, let data):
            return data.help ?? data.sceneID
        }
    }

    var body: some View {
        switch self {
        case .project:
            ProjectNavigatorView()
        case .sourceControl:
            SourceControlNavigatorView()
        case .search:
            FindNavigatorView()
        case .problems:
            ProblemsView()
        case .breakpoints:
            BreakpointsView()
        case let .uiExtension(endpoint, data):
            ExtensionSceneView(with: endpoint, sceneID: data.sceneID)
        }
    }

    @ViewBuilder
    func bottomView(workspace: WorkspaceDocument) -> some View {
        switch self {
        case .project:
            ProjectNavigatorToolbarBottom()
        case .sourceControl:
            if let sourceControlManager = workspace.sourceControlManager {
                SourceControlNavigatorToolbarBottom()
                    .environmentObject(sourceControlManager)
            }
        case .search:
            FindNavigatorToolbarBottom()
        case .problems:
            ProblemsNavigatorToolbarBottom()
        case .breakpoints:
            BreakpointsNavigatorToolbarBottom()
        case .uiExtension:
            EmptyView()
        }
    }
}
