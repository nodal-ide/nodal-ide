//
//  KnowledgeSearch.swift
//  CodeEdit
//
//  Full-text search across knowledge base pages.
//

import Foundation

/// A single full-text search hit.
struct KnowledgeSearchResult: Identifiable, Hashable {
    let id: String
    let sourceID: String
    let sourceTitle: String
    let path: String
    let title: String
    let snippet: String
}

/// Caches page text and searches it. Texts are read once per source and reused.
final class KnowledgeSearchIndex {
    static let shared = KnowledgeSearchIndex()

    private let lock = NSLock()
    private var cache: [String: [String: String]] = [:]

    private init() {}

    /// Page path → raw text for a source (cached).
    func texts(for source: KnowledgeSource) -> [String: String] {
        lock.lock()
        if let cached = cache[source.id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var texts: [String: String] = [:]
        for page in source.pages {
            guard let path = page.path.map(KnowledgeSource.normalize),
                  let content = source.content(for: path) else { continue }
            texts[path] = content
        }

        lock.lock()
        cache[source.id] = texts
        lock.unlock()
        return texts
    }

    /// Searches a source's page bodies (and falls back to title matches).
    func search(_ query: String, in source: KnowledgeSource, limit: Int = 50) -> [KnowledgeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let texts = texts(for: source)
        var results: [KnowledgeSearchResult] = []

        for page in source.pages {
            guard let path = page.path.map(KnowledgeSource.normalize) else { continue }
            let titleMatches = page.title.localizedCaseInsensitiveContains(trimmed)

            var snippet = ""
            if let text = texts[path], let range = text.range(of: trimmed, options: .caseInsensitive) {
                snippet = Self.snippet(text, around: range)
            } else if !titleMatches {
                continue
            }

            results.append(
                KnowledgeSearchResult(
                    id: "\(source.id):\(path)",
                    sourceID: source.id,
                    sourceTitle: source.title,
                    path: path,
                    title: page.title,
                    snippet: snippet
                )
            )
            if results.count >= limit { break }
        }

        return results
    }

    /// Searches several sources (e.g. the quick-lookup panel).
    func search(_ query: String, in sources: [KnowledgeSource], limitPerSource: Int = 25) -> [KnowledgeSearchResult] {
        sources.flatMap { search(query, in: $0, limit: limitPerSource) }
    }

    func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func snippet(_ text: String, around range: Range<String.Index>, radius: Int = 70) -> String {
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}

/// Routes "open this page" requests to the Knowledge window (which may not be open yet).
final class KnowledgeRouter {
    static let shared = KnowledgeRouter()
    static let didRequestOpen = Notification.Name("CodeEdit.KnowledgeRouter.didRequestOpen")

    struct Request: Sendable {
        let sourceID: String?
        let path: String
    }

    private var pending: Request?

    private init() {}

    func requestOpen(sourceID: String?, path: String) {
        let request = Request(sourceID: sourceID, path: path)
        pending = request
        NotificationCenter.default.post(name: Self.didRequestOpen, object: request)
    }

    /// Consumes a queued request (used when the window is created for a request).
    func consumePending() -> Request? {
        defer { pending = nil }
        return pending
    }

    func clearPending() {
        pending = nil
    }
}
