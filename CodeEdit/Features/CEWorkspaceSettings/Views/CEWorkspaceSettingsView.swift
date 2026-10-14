//
//  CEWorkspaceSettingsView.swift
//  CodeEdit
//
//  Created by Tommy Ludwig on 01.07.24.
//

import SwiftUI

struct CEWorkspaceSettingsView: View {
    var dismiss: () -> Void

    @EnvironmentObject var workspaceSettingsManager: CEWorkspaceSettings
    @EnvironmentObject var workspace: WorkspaceDocument

    @State var selectedTaskID: UUID?
    @State var showAddTaskSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(
                        "Name",
                        text: $workspaceSettingsManager.settings.project.projectName
                    )
                    .accessibilityLabel("Workspace Name")
                } header: {
                    Text("Workspace")
                        .accessibilityHidden(true)
                }

                Section {
                    TextField(
                        "Language",
                        text: $workspaceSettingsManager.settings.project.language,
                        prompt: Text("php")
                    )
                    .accessibilityLabel("Project Language")

                    TextField(
                        "Frameworks",
                        text: frameworksBinding,
                        prompt: Text("laravel/framework, symfony/symfony")
                    )
                    .accessibilityLabel("Project Frameworks")

                    Text("Comma-separated. Activates matching language extensions without scanning the project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Languages")
                }
                .onChange(of: workspaceSettingsManager.settings.project.language) { _, _ in reloadExtensions() }
                .onChange(of: workspaceSettingsManager.settings.project.frameworks) { _, _ in reloadExtensions() }

                Section {
                    CEWorkspaceSettingsTaskListView(
                        settings: workspaceSettingsManager.settings,
                        selectedTaskID: $selectedTaskID,
                        showAddTaskSheet: $showAddTaskSheet
                    )
                } header: {
                    Text("Tasks")
                } footer: {
                    HStack {
                        Spacer()
                        Button {
                            selectedTaskID = nil
                            showAddTaskSheet = true
                        } label: {
                            Text("Add Task...")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

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
            }
            .padding()
        }
        .sheet(isPresented: $showAddTaskSheet) {
            if let selectedTaskIndex = workspaceSettingsManager.settings.tasks.firstIndex(where: {
                $0.id == selectedTaskID
            }) {
                EditCETaskView(
                    task: workspaceSettingsManager.settings.tasks[selectedTaskIndex],
                    selectedTaskIndex: selectedTaskIndex
                )
            } else {
                AddCETaskView()
            }
        }
    }

    /// Comma-separated editing binding over the frameworks array.
    private var frameworksBinding: Binding<String> {
        Binding {
            workspaceSettingsManager.settings.project.frameworks.joined(separator: ", ")
        } set: { newValue in
            workspaceSettingsManager.settings.project.frameworks = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    /// Re-evaluates language extensions for this workspace after the project language/frameworks change.
    private func reloadExtensions() {
        guard let root = workspace.fileURL else { return }
        LanguageProviderRegistry.shared.reloadExtensions(for: root)
    }
}

#Preview {
    CEWorkspaceSettingsView(dismiss: { print("Dismiss") })
}
