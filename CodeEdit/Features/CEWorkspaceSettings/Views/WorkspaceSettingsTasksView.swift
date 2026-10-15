//
//  WorkspaceSettingsTasksView.swift
//  CodeEdit
//
//  The "Tasks" page of the Project Settings window.
//

import SwiftUI

struct WorkspaceSettingsTasksView: View {
    @EnvironmentObject private var workspaceSettingsManager: CEWorkspaceSettings
    @EnvironmentObject private var taskManager: TaskManager

    @State private var selectedTaskID: UUID?
    @State private var showTaskSheet = false

    var body: some View {
        Form {
            Section {
                CEWorkspaceSettingsTaskListView(
                    settings: workspaceSettingsManager.settings,
                    selectedTaskID: $selectedTaskID,
                    showAddTaskSheet: $showTaskSheet
                )
            } header: {
                Text("Tasks")
            } footer: {
                HStack {
                    Text("Tasks run shell commands and can match problems into the Issues navigator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Task…") {
                        selectedTaskID = nil
                        showTaskSheet = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showTaskSheet) {
            if let index = workspaceSettingsManager.settings.tasks.firstIndex(where: { $0.id == selectedTaskID }) {
                EditCETaskView(task: workspaceSettingsManager.settings.tasks[index], selectedTaskIndex: index)
            } else {
                AddCETaskView()
            }
        }
    }
}
