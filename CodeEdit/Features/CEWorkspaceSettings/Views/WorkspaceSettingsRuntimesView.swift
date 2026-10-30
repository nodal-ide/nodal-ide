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
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Pin the PHP and Node.js versions this project uses. "
                        + "Versions are installed in the Runtime Manager (Runtimes ▸ Manage Runtimes…)."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(missingPins, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
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
        .onReceive(AppServices.runtimeManager.runtimesDidChange) { _ in
            Task { await loadInstalled() }
        }
    }

    // MARK: - Pickers

    private func versionPicker(kind: RuntimeKind, installed: [InstalledRuntime]) -> some View {
        let current = pinnedVersion(kind)
        return LabeledContent(kind.title) {
            Menu {
                Button {
                    setVersion(nil, kind: kind)
                } label: {
                    menuLabel(inheritTitle(for: kind), selected: current == nil)
                }

                Divider()

                ForEach(installed) { runtime in
                    Button {
                        setVersion(runtime.version, kind: kind)
                    } label: {
                        menuLabel(
                            "v\(runtime.version) — \(runtime.source.title)",
                            selected: current == runtime.version
                        )
                    }
                }

                if let current, !installed.contains(where: { $0.version == current }) {
                    Divider()
                    Button {
                        setVersion(current, kind: kind)
                    } label: {
                        menuLabel("v\(current) — not installed", selected: true)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current.map { "v\($0)" } ?? "Inherit")
                        .foregroundStyle(current == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .accessibilityLabel("\(kind.title) version")
    }

    private func menuLabel(_ text: String, selected: Bool) -> some View {
        HStack {
            Text(text)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var packageManagerField: some View {
        TextField("Node package manager", text: packageManagerBinding, prompt: Text("pnpm@9"))
            .accessibilityLabel("Node package manager")
    }

    // MARK: - Bindings

    private func pinnedVersion(_ kind: RuntimeKind) -> String? {
        workspaceSettingsManager.settings.runtimes.selection(for: kind).version
    }

    private func setVersion(_ version: String?, kind: RuntimeKind) {
        var runtimes = workspaceSettingsManager.settings.runtimes
        var selection = runtimes.selection(for: kind)
        selection.version = version
        runtimes.setSelection(selection, for: kind)
        workspaceSettingsManager.settings.runtimes = runtimes
    }

    private var packageManagerBinding: Binding<String> {
        Binding {
            workspaceSettingsManager.settings.runtimes.node.packageManager ?? ""
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            var runtimes = workspaceSettingsManager.settings.runtimes
            runtimes.node.packageManager = trimmed.isEmpty ? nil : trimmed
            workspaceSettingsManager.settings.runtimes = runtimes
        }
    }

    // MARK: - Helpers

    private var missingPins: [String] {
        var result: [String] = []
        if let php = pinnedVersion(.php), !installedPHP.contains(where: { $0.version == php }) {
            result.append("PHP v\(php) isn't installed — the terminal will use the newest installed PHP.")
        }
        if let node = pinnedVersion(.node), !installedNode.contains(where: { $0.version == node }) {
            result.append("Node v\(node) isn't installed — the terminal will use the newest installed Node.")
        }
        return result
    }

    private func inheritTitle(for kind: RuntimeKind) -> String {
        if let global = AppServices.settings.preferences.developerSettings.defaultRuntimeVersions[kind.rawValue],
           !global.isEmpty {
            return "Inherit global default (v\(global))"
        }
        return "Inherit global default"
    }

    private func loadInstalled() async {
        if let provider = AppServices.runtimeManager.provider(for: .php) {
            installedPHP = await provider.installedVersions()
        }
        if let provider = AppServices.runtimeManager.provider(for: .node) {
            installedNode = await provider.installedVersions()
        }
    }
}
