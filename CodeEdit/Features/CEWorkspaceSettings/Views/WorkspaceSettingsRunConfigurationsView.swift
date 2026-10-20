//
//  WorkspaceSettingsRunConfigurationsView.swift
//  CodeEdit
//
//  The "Run & Debug" page of the Project Settings window.
//

import SwiftUI

struct WorkspaceSettingsRunConfigurationsView: View {
    var onEditLocalDomain: (() -> Void)?

    @EnvironmentObject private var workspaceSettingsManager: CEWorkspaceSettings
    @EnvironmentObject private var workspace: WorkspaceDocument

    @State private var selectedID: UUID?
    @State private var showEditor = false

    var body: some View {
        Form {
            if let store = workspace.runConfigurationStore {
                Section {
                    RunConfigurationListView(
                        store: store,
                        selectedID: $selectedID,
                        showEditor: $showEditor,
                        site: workspaceSettingsManager.settings.site
                    )
                } header: {
                    Text("Run Configurations")
                } footer: {
                    HStack {
                        Text("Run configurations are stored in this project and run from the Run menu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Add Configuration…") {
                            selectedID = nil
                            showEditor = true
                        }
                    }
                }
            } else {
                Section {
                    Text("Run configurations are unavailable for this project.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showEditor) {
            if let store = workspace.runConfigurationStore {
                let taskNames = workspaceSettingsManager.settings.tasks.map(\.name)
                if let id = selectedID, let configuration = store.configurations.first(where: { $0.id == id }) {
                    RunConfigurationEditorSheet(
                        store: store,
                        configuration: configuration,
                        taskNames: taskNames,
                        site: workspaceSettingsManager.settings.site,
                        onEditLocalDomain: onEditLocalDomain
                    )
                } else {
                    RunConfigurationEditorSheet(
                        store: store,
                        configuration: nil,
                        taskNames: taskNames,
                        site: workspaceSettingsManager.settings.site,
                        onEditLocalDomain: onEditLocalDomain
                    )
                }
            }
        }
    }
}
