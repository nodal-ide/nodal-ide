//
//  CEWorkspaceSettingsView.swift
//  CodeEdit
//
//  The Project (Workspace) Settings window: a sidebar of pages with grouped detail panes.
//

import SwiftUI

struct CEWorkspaceSettingsView: View {
    var dismiss: () -> Void

    @EnvironmentObject var workspaceSettingsManager: CEWorkspaceSettings
    @EnvironmentObject var workspace: WorkspaceDocument

    @State private var selection: WorkspaceSettingsPage = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.title)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .frame(minWidth: 720, minHeight: 540)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(WorkspaceSettingsPage.allCases) { page in
                    Label {
                        Text(page.title)
                    } icon: {
                        FeatureIcon(symbol: page.systemImage, color: page.baseColor, size: 20)
                    }
                    .tag(page)
                }
            }
        }
        .navigationSplitViewColumnWidth(200)
        .navigationTitle(projectName)
    }

    private var detail: some View {
        Group {
            switch selection {
            case .general:
                WorkspaceSettingsGeneralView()
            case .tasks:
                WorkspaceSettingsTasksView()
            case .runConfigurations:
                WorkspaceSettingsRunConfigurationsView()
            case .runtimes:
                WorkspaceSettingsRuntimesView()
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .background(.bar)
    }

    private var projectName: String {
        let name = workspaceSettingsManager.settings.project.projectName
        return name.isEmpty ? "Project" : name
    }
}

#Preview {
    CEWorkspaceSettingsView(dismiss: { print("Dismiss") })
}
