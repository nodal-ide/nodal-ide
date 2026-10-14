//
//  KnowledgeViewModel.swift
//  CodeEdit
//

import Foundation

/// State for the Knowledge Base window: selected source, current page, history and search.
@MainActor
final class KnowledgeViewModel: ObservableObject {
    @Published var sources: [KnowledgeSource] = []
    @Published var selectedSourceID: String?
    @Published var currentPath: String?
    @Published var fragment: String?
    @Published var searchText: String = ""

    private(set) var history: [String] = []
    private var historyIndex = -1

    init() {
        reload()
    }

    func reload() {
        sources = KnowledgeRegistry.shared.sources
        if let current = sources.first(where: { $0.id == selectedSourceID }) {
            selectedSourceID = current.id
        } else if let first = sources.first {
            selectSource(first)
        }
    }

    var selectedSource: KnowledgeSource? {
        sources.first { $0.id == selectedSourceID }
    }

    /// Selects a source and opens its home page.
    func selectSource(_ source: KnowledgeSource) {
        selectedSourceID = source.id
        history = []
        historyIndex = -1
        open(path: source.homePage)
    }

    /// Opens a page (path may include a `#fragment`).
    func open(path rawPath: String, pushHistory: Bool = true) {
        guard let source = selectedSource else { return }

        var path = rawPath
        var fragment: String?
        if let hash = rawPath.firstIndex(of: "#") {
            path = String(rawPath[..<hash])
            fragment = String(rawPath[rawPath.index(after: hash)...])
        }

        var resolved = KnowledgeSource.normalize(path)
        if resolved.isEmpty {
            resolved = source.homePage
        }
        // Allow links without an extension to resolve to a Markdown page.
        if source.content(for: resolved) == nil, !resolved.contains(".") {
            let markdown = resolved + ".md"
            if source.content(for: markdown) != nil {
                resolved = markdown
            }
        }

        currentPath = resolved
        self.fragment = fragment

        guard pushHistory else { return }
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        history.append(resolved)
        historyIndex = history.count - 1
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        open(path: history[historyIndex], pushHistory: false)
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        open(path: history[historyIndex], pushHistory: false)
    }

    func goHome() {
        guard let source = selectedSource else { return }
        open(path: source.homePage)
    }

    /// Pages whose title or path match the current search text.
    var searchResults: [KnowledgeIndex.TOCItem] {
        guard let source = selectedSource, !trimmedSearchText.isEmpty else { return [] }
        return source.pages.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedSearchText)
                || ($0.path?.localizedCaseInsensitiveContains(trimmedSearchText) ?? false)
        }
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The rendered HTML for the current page.
    var currentHTML: String? {
        guard let source = selectedSource, let path = currentPath else { return nil }
        return KnowledgeRenderer.html(forPath: path, source: source)
    }
}
