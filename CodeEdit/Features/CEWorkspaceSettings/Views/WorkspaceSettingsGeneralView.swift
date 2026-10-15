//
//  WorkspaceSettingsGeneralView.swift
//  CodeEdit
//
//  The "General" page of the Project Settings window.
//

import SwiftUI

struct WorkspaceSettingsGeneralView: View {
    @EnvironmentObject private var workspaceSettingsManager: CEWorkspaceSettings
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        Form {
            Section {
                TextField(
                    "Name",
                    text: $workspaceSettingsManager.settings.project.projectName,
                    prompt: Text("My Project")
                )
                .accessibilityLabel("Workspace Name")
            } header: {
                Text("Workspace")
            } footer: {
                Text("Shown in the window title and the Project navigator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            } header: {
                Text("Languages")
            } footer: {
                Text(
                    "Comma-separated. Activates matching language extensions without scanning the project."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .onChange(of: workspaceSettingsManager.settings.project.language) { _, _ in reloadExtensions() }
            .onChange(of: workspaceSettingsManager.settings.project.frameworks) { _, _ in reloadExtensions() }
        }
        .formStyle(.grouped)
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
