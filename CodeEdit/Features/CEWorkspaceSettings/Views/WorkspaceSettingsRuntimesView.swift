//
//  WorkspaceSettingsRuntimesView.swift
//  CodeEdit
//
//  The "Runtimes" page of the Project Settings window (PHP/Node pins + Node package manager).
//

import SwiftUI

struct WorkspaceSettingsRuntimesView: View {
    @EnvironmentObject private var workspaceSettingsManager: CEWorkspaceSettings

    @State private var installedPHP: [InstalledRuntime] = []
    @State private var installedNode: [InstalledRuntime] = []

    var body: some View {
        Form {
            Section {
                versionPicker(kind: .php, installed: installedPHP)
                versionPicker(kind: .node, installed: installedNode)
            } header: {
                Text("Versions")
            } footer: {
                Text(
                    "Pin the PHP and Node.js versions this project uses. "
                    + "Versions are installed in the Runtime Manager (Runtimes ▸ Manage Runtimes…)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                packageManagerField
            } header: {
                Text("Package Managers")
            } footer: {
                Text("Optional. Activated via corepack for the pinned Node.js version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await loadInstalled() }
    }

    // MARK: - Pickers

    private func versionPicker(kind: RuntimeKind, installed: [InstalledRuntime]) -> some View {
        Picker(kind.title, selection: versionBinding(kind)) {
            Text(inheritTitle(for: kind)).tag("")
            ForEach(installed) { runtime in
                Text("v\(runtime.version) — \(runtime.source.title)").tag(runtime.version)
            }
        }
        .accessibilityLabel("\(kind.title) version")
    }

    private var packageManagerField: some View {
        TextField("Node package manager", text: packageManagerBinding, prompt: Text("pnpm@9"))
            .accessibilityLabel("Node package manager")
    }

    // MARK: - Bindings

    private func versionBinding(_ kind: RuntimeKind) -> Binding<String> {
        Binding {
            workspaceSettingsManager.settings.runtimes.selection(for: kind).version ?? ""
        } set: { newValue in
            var selection = workspaceSettingsManager.settings.runtimes.selection(for: kind)
            selection.version = newValue.isEmpty ? nil : newValue
            workspaceSettingsManager.settings.runtimes.setSelection(selection, for: kind)
        }
    }

    private var packageManagerBinding: Binding<String> {
        Binding {
            workspaceSettingsManager.settings.runtimes.node.packageManager ?? ""
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            workspaceSettingsManager.settings.runtimes.node.packageManager = trimmed.isEmpty ? nil : trimmed
        }
    }

    // MARK: - Helpers

    private func inheritTitle(for kind: RuntimeKind) -> String {
        if let global = Settings.shared.preferences.developerSettings.defaultRuntimeVersions[kind.rawValue],
           !global.isEmpty {
            return "Inherit global default (v\(global))"
        }
        return "Inherit global default"
    }

    private func loadInstalled() async {
        if let provider = RuntimeManager.shared.provider(for: .php) {
            installedPHP = await provider.installedVersions()
        }
        if let provider = RuntimeManager.shared.provider(for: .node) {
            installedNode = await provider.installedVersions()
        }
    }
}
