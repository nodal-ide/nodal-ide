//
//  ExtensionsSettingsView.swift
//  CodeEdit
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings page for managing installed language extensions (declarative packs).
struct ExtensionsSettingsView: View {
    @AppSettings(\.extensions.disabledExtensions)
    var disabledExtensions

    @State private var extensions: [InstalledLanguageExtension] = []
    @State private var errorMessage: String?

    var body: some View {
        SettingsForm {
            Section {
                if extensions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No language extensions installed")
                        Text("Add a pack to get framework completion, documentation and go-to-definition.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(extensions) { ext in
                        row(for: ext)
                    }
                }
            } header: {
                Text("Language Extensions")
                Text("Data-only packs that add framework/library symbols and documentation.")
            }

            Section {
                HStack {
                    Button("Add from Folder…") { installFromFolder() }
                    Button("Add from Archive…") { installFromArchive() }
                    Spacer()
                    Button("Reload") { reload() }
                    Button("Reveal Folder") { revealFolder() }
                }
            } header: {
                Text("Manage")
                Text("Extensions are stored in \(LanguageExtensionStore.globalExtensionsDirectory.path(percentEncoded: false)).")
            }
        }
        .onAppear { reload() }
        .alert(
            "Extension Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func row(for ext: InstalledLanguageExtension) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name)
                HStack(spacing: 6) {
                    Text(ext.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let version = ext.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let framework = ext.manifest.frameworkName {
                        Text(framework)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Toggle("Enabled", isOn: enabledBinding(ext))
                .labelsHidden()
            Button(role: .destructive) {
                remove(ext)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove extension")
        }
    }

    private func enabledBinding(_ ext: InstalledLanguageExtension) -> Binding<Bool> {
        Binding {
            !disabledExtensions.contains(ext.id)
        } set: { enabled in
            var list = disabledExtensions
            list.removeAll { $0 == ext.id }
            if !enabled {
                list.append(ext.id)
            }
            disabledExtensions = list
            LanguageProviderRegistry.shared.reloadAllExtensions()
        }
    }

    private func reload() {
        extensions = LanguageExtensionStore.shared.globalExtensions()
    }

    private func installFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Install"
        panel.message = "Choose a folder containing an extension.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try LanguageExtensionStore.shared.install(fromFolder: url)
            reload()
            LanguageProviderRegistry.shared.reloadAllExtensions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installFromArchive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.prompt = "Install"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try LanguageExtensionStore.shared.install(fromZip: url)
            reload()
            LanguageProviderRegistry.shared.reloadAllExtensions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ ext: InstalledLanguageExtension) {
        do {
            try LanguageExtensionStore.shared.remove(ext)
            disabledExtensions.removeAll { $0 == ext.id }
            reload()
            LanguageProviderRegistry.shared.reloadAllExtensions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revealFolder() {
        let directory = LanguageExtensionStore.globalExtensionsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }
}
