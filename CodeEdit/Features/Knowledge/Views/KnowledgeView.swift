//
//  KnowledgeView.swift
//  CodeEdit
//

import SwiftUI
import AppKit

/// The Knowledge Base: sources, table of contents and a rendered page.
struct KnowledgeView: View {
    @ObservedObject var model: KnowledgeViewModel

    @State private var importError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: sourceSelectionBinding) {
                ForEach(model.sources) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                        if let subtitle = source.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(source.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } content: {
            tocContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
                .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search pages")
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                    .help("Back")
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .help("Forward")
                Button { model.goHome() } label: { Image(systemName: "house") }
                    .help("Home")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Import Docset…") { importDocset() }
                    Button("Reveal Sources Folder") {
                        let directory = KnowledgeRegistry.userKnowledgeDirectory
                        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([directory])
                    }
                    Divider()
                    Button("Reload Sources") { reloadSources() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(
            "Import Failed",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .navigationTitle(model.selectedSource?.title ?? "Knowledge")
    }

    private func importDocset() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a .docset bundle"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try AppServices.knowledgeRegistry.importDocset(from: url)
            model.reload()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func reloadSources() {
        AppServices.knowledgeSearchIndex.invalidate()
        AppServices.knowledgeRegistry.reload()
        model.reload()
    }

    private var sourceSelectionBinding: Binding<String?> {
        Binding {
            model.selectedSourceID
        } set: { id in
            guard let id, let source = model.sources.first(where: { $0.id == id }) else { return }
            model.selectSource(source)
        }
    }

    @ViewBuilder private var tocContent: some View {
        if !model.trimmedSearchText.isEmpty {
            if model.searchResults.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
            } else {
                List(model.searchResults) { result in
                    searchResultRow(result)
                }
            }
        } else if let source = model.selectedSource {
            List {
                ForEach(source.index.toc) { item in
                    tocRows(item)
                }
            }
        } else {
            Text("No source selected")
                .foregroundStyle(.secondary)
        }
    }

    private func searchResultRow(_ result: KnowledgeSearchResult) -> some View {
        Button {
            model.open(path: result.path)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tocRows(_ item: KnowledgeIndex.TOCItem) -> AnyView {
        if let children = item.children, !children.isEmpty {
            return AnyView(
                DisclosureGroup(item.title) {
                    ForEach(children) { child in
                        tocRows(child)
                    }
                }
            )
        } else if let path = item.path {
            return AnyView(
                Button {
                    model.open(path: path)
                } label: {
                    let isCurrent = KnowledgeSource.normalize(path) == model.currentPath
                    Text(item.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    private func tocButton(_ item: KnowledgeIndex.TOCItem) -> some View {
        let isCurrent = item.path.map { KnowledgeSource.normalize($0) == model.currentPath } ?? false
        return Button {
            if let path = item.path { model.open(path: path) }
        } label: {
            Text(item.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
    }

    @ViewBuilder private var detail: some View {
        if let html = model.currentHTML {
            KnowledgeWebView(
                html: html,
                baseURL: model.selectedSource?.baseURL,
                fragment: model.fragment,
                highlight: model.trimmedSearchText.isEmpty ? nil : model.trimmedSearchText,
                onNavigate: { model.open(path: $0) },
                onExternal: { NSWorkspace.shared.open($0) }
            )
        } else {
            Text("Select a page")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
