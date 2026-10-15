//
//  KnowledgeQuickSearchView.swift
//  CodeEdit
//
//  A quick-lookup palette for the knowledge base (⌥⌘K).
//

import SwiftUI

struct KnowledgeQuickSearchView: View {
    @Environment(\.openWindow)
    private var openWindow

    @State private var query = ""
    @State private var results: [KnowledgeSearchResult] = []

    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        SearchPanelView<AnyView, EmptyView, KnowledgeSearchResult>(
            title: "Search knowledge base…",
            image: Image(systemName: "book"),
            options: $results,
            text: $query,
            alwaysShowOptions: true,
            optionRowHeight: 44,
            content: { result in
                AnyView(KnowledgeQuickSearchRow(result: result))
            },
            preview: nil,
            onRowClick: { result in
                KnowledgeRouter.shared.requestOpen(sourceID: result.sourceID, path: result.path)
                openWindow(sceneID: .knowledge)
                onClose()
            },
            onClose: {
                onClose()
            }
        )
        .onChange(of: query) { _, _ in update() }
    }

    private func update() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        results = KnowledgeSearchIndex.shared.search(trimmed, in: KnowledgeRegistry.shared.sources)
    }
}

private struct KnowledgeQuickSearchRow: View {
    let result: KnowledgeSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(result.title)
                    .fontWeight(.medium)
                Spacer()
                Text(result.sourceTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
