//
//  KnowledgeView.swift
//  CodeEdit
//

import SwiftUI
import AppKit

/// The Knowledge Base: sources, table of contents and a rendered page.
struct KnowledgeView: View {
    @ObservedObject var model: KnowledgeViewModel

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
        }
        .navigationTitle(model.selectedSource?.title ?? "Knowledge")
        .onChange(of: model.selectedSourceID) { _, _ in }
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
                Text("No matching pages")
                    .foregroundStyle(.secondary)
            } else {
                List(model.searchResults) { item in
                    tocButton(item)
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
