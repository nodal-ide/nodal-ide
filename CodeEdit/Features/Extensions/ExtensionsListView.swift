//
//  ExtensionsListView.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 24/03/2023.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExtensionsListView: View {
    @EnvironmentObject var manager: ExtensionManager
    @EnvironmentObject var languageManager: LanguageExtensionManager
    @Binding var selection: Set<ExtensionItem>

    @AppSettings(\.extensions.disabledExtensions)
    private var disabledExtensions

    @State var showActivatorView = false
    @State private var errorMessage: String?

    private var languageItems: [ExtensionItem] { languageManager.extensions.map(ExtensionItem.language) }
    private var appItems: [ExtensionItem] { manager.extensions.map(ExtensionItem.app) }

    var body: some View {
        List(selection: $selection) {
            if !languageItems.isEmpty {
                Section("Language Extensions") {
                    ForEach(languageItems) { item in
                        row(item)
                    }
                }
            }

            if !appItems.isEmpty {
                Section("App Extensions") {
                    ForEach(appItems) { item in
                        row(item)
                    }
                }
            }

            if languageItems.isEmpty && appItems.isEmpty {
                Text("No extensions installed")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add from Folder…") { installFromFolder() }
                    Button("Add from Archive…") { installFromArchive() }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Install a language extension")
            }
            ToolbarItem {
                Button {
                    languageManager.reloadAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload extensions")
            }
            ToolbarItem {
                Toggle(isOn: $showActivatorView) {
                    Image(systemName: "puzzlepiece.extension")
                }
                .toggleStyle(.button)
                .popover(isPresented: $showActivatorView) {
                    ExtensionActivatorView()
                        .frame(width: 400, height: 300)
                }
                .help("Browse app extensions")
            }
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: languageManager.extensions) { _, _ in selectFirstIfNeeded() }
        .onChange(of: manager.extensions) { _, _ in selectFirstIfNeeded() }
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
    private func row(_ item: ExtensionItem) -> some View {
        HStack(spacing: 8) {
            switch item {
            case .language(let ext):
                Image(nsImage: ext.icon)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading) {
                    Text(ext.name)
                    if let subtitle = ext.subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            case .app(let info):
                if let icon = info.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading) {
                    Text(info.name)
                    if let version = info.version {
                        Text(version)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 40)
        .tag(item)
        .contextMenu {
            if case .language(let ext) = item {
                Toggle("Enabled", isOn: enabledBinding(ext))
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ext.root])
                }
                Divider()
                Button("Remove Extension", role: .destructive) {
                    try? languageManager.remove(ext)
                }
            }
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

    /// Selects the first available extension when nothing is selected.
    private func selectFirstIfNeeded() {
        guard selection.isEmpty, let first = (languageItems + appItems).first else { return }
        selection = [first]
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
            try languageManager.install(fromFolder: url)
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
            try languageManager.install(fromZip: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
