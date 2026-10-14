//
//  KnowledgeSource.swift
//  CodeEdit
//
//  Models for offline knowledge bases (Markdown/HTML docs + an index).
//

import Foundation

/// A knowledge base source: a set of documentation pages with a table of contents.
struct KnowledgeSource: Identifiable, Hashable {
    enum Storage: Hashable {
        /// Pages live on disk under `root`.
        case disk(root: URL)
        /// Pages are provided in memory (built-in docs).
        case memory(pages: [String: String])
    }

    let id: String
    let title: String
    let subtitle: String?
    let storage: Storage
    let index: KnowledgeIndex

    static func == (lhs: KnowledgeSource, rhs: KnowledgeSource) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The raw Markdown/HTML for a page path (relative to the source root).
    func content(for path: String) -> String? {
        let normalized = Self.normalize(path)
        switch storage {
        case .disk(let root):
            return try? String(contentsOf: root.appending(path: normalized), encoding: .utf8)
        case .memory(let pages):
            return pages[normalized]
        }
    }

    /// The directory pages resolve against (for `WKWebView` base URL), or `nil` for in-memory pages.
    var baseURL: URL? {
        if case .disk(let root) = storage { return root }
        return nil
    }

    /// The home page path (defaults to `README.md`).
    var homePage: String { index.home ?? "README.md" }

    /// All leaf pages in the table of contents.
    var pages: [KnowledgeIndex.TOCItem] {
        func leaves(_ items: [KnowledgeIndex.TOCItem]) -> [KnowledgeIndex.TOCItem] {
            items.flatMap { item in
                var result: [KnowledgeIndex.TOCItem] = []
                if let path = item.path { result.append(KnowledgeIndex.TOCItem(title: item.title, path: path)) }
                if let children = item.children { result.append(contentsOf: leaves(children)) }
                return result
            }
        }
        return leaves(index.toc)
    }

    static func normalize(_ path: String) -> String {
        var result = path
        while result.hasPrefix("./") { result.removeFirst(2) }
        return result
    }
}

/// The `index.json` of a knowledge pack.
struct KnowledgeIndex: Codable {
    var title: String
    var subtitle: String?
    var home: String?
    var keywords: [String]?
    var toc: [TOCItem]

    struct TOCItem: Codable, Identifiable, Hashable {
        var title: String
        var path: String?
        var children: [TOCItem]?

        var id: String { (path ?? "") + "|" + title }
    }
}
