//
//  ExtensionProjectScope.swift
//  CodeEdit
//
//  Per-project activation overrides for installed language extensions.
//

import SwiftUI
import AppKit

/// One open workspace that can carry project-level extension activation overrides.
struct ExtensionProjectScope: Identifiable {
    let root: URL
    let settings: CEWorkspaceSettings

    var id: String { root.standardizedFileURL.path(percentEncoded: false) }

    var displayName: String {
        let name = settings.settings.project.projectName
        return name.isEmpty ? root.lastPathComponent : name
    }
}

/// Loads the open workspaces and persists project extension overrides to their settings files.
@MainActor
final class ExtensionProjectScopeModel: ObservableObject {
    @Published private(set) var projects: [ExtensionProjectScope] = []
    @Published private(set) var errorMessage: String?

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        })
        observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Rebuilds the project list from open workspace documents, without scanning their trees.
    func refresh() {
        var seen: Set<String> = []
        projects = NSDocumentController.shared.documents.compactMap { document in
            guard let workspace = document as? WorkspaceDocument,
                  let root = workspace.fileURL,
                  let settings = workspace.workspaceSettingsManager else {
                return nil
            }
            let project = ExtensionProjectScope(root: root, settings: settings)
            return seen.insert(project.id).inserted ? project : nil
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Sets or removes one override and re-evaluates only that workspace.
    func setOverride(
        _ override: ExtensionActivationOverride?,
        for extensionID: String,
        in project: ExtensionProjectScope
    ) {
        let projectSettings = project.settings.settings.project
        let previous = projectSettings.extensionOverrides[extensionID]

        if let override {
            projectSettings.extensionOverrides[extensionID] = override
        } else {
            projectSettings.extensionOverrides[extensionID] = nil
        }

        do {
            try project.settings.savePreferences()
        } catch {
            projectSettings.extensionOverrides[extensionID] = previous
            errorMessage = error.localizedDescription
            return
        }

        LanguageExtensionActivation.invalidate(root: project.root)
        AppServices.languageProviderRegistry.reloadExtensions(for: project.root)
        refresh()
    }

    func clearError() {
        errorMessage = nil
    }
}

/// Project activation controls for one installed extension.
struct ProjectExtensionScopeSection: View {
    let ext: InstalledLanguageExtension

    @StateObject private var model = ExtensionProjectScopeModel()

    var body: some View {
        Section("Project Activation") {
            if model.projects.isEmpty {
                Text("Open a project to enable or disable this extension per project.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.projects) { project in
                    ProjectExtensionScopeRow(ext: ext, project: project) { override in
                        model.setOverride(override, for: ext.id, in: project)
                    }
                }
            }

            Text(
                "Project overrides take precedence over activation rules. Disabling an extension "
                    + "globally still disables it in every project."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear { model.refresh() }
        .alert(
            "Could Not Update Project Scope",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct ProjectExtensionScopeRow: View {
    let ext: InstalledLanguageExtension
    let project: ExtensionProjectScope
    let onChange: (ExtensionActivationOverride?) -> Void

    private var activation: LanguageExtensionActivation.Result {
        LanguageExtensionActivation.evaluate(ext, in: project.root)
    }

    private enum ActivationSelection: Hashable {
        case global
        case enabled
        case disabled
    }

    private var selectionBinding: Binding<ActivationSelection> {
        Binding {
            switch project.settings.settings.project.extensionOverrides[ext.id] {
            case .enabled: .enabled
            case .disabled: .disabled
            case nil: .global
            }
        } set: { selection in
            switch selection {
            case .global: onChange(nil)
            case .enabled: onChange(.enabled)
            case .disabled: onChange(.disabled)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activation.isActive ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(activation.isActive ? .green : .secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.callout)
                Text(project.root.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(activation.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Picker("Activation", selection: selectionBinding) {
                Text("Use Global Rules").tag(ActivationSelection.global)
                Text("Enabled").tag(ActivationSelection.enabled)
                Text("Disabled").tag(ActivationSelection.disabled)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 160)
            .accessibilityLabel("Activation in \(project.displayName)")
        }
    }
}
