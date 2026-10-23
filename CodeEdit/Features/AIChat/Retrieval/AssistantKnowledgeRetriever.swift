import Foundation

@MainActor
enum AssistantKnowledgeRetriever {
    static func retrieve(query: String, limit: Int = 4) -> [AssistantKnowledgeExcerpt] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let index = KnowledgeSearchIndex.shared
        let sources = KnowledgeRegistry.shared.sources
        guard !sources.isEmpty else { return [] }

        var candidates = [trimmed]
        candidates.append(
            contentsOf: AssistantRetrievalTokenizer.terms(in: trimmed)
                .filter { $0.count >= 3 }
                .prefix(4)
        )

        var excerpts: [AssistantKnowledgeExcerpt] = []
        var seen = Set<String>()
        for candidate in candidates {
            for source in sources {
                for result in index.search(candidate, in: source, limit: 2) {
                    guard seen.insert(result.id).inserted else { continue }
                    let snippet = result.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !snippet.isEmpty else { continue }
                    excerpts.append(
                        AssistantKnowledgeExcerpt(
                            id: result.id,
                            sourceID: result.sourceID,
                            pagePath: result.path,
                            title: result.title,
                            text: "\(result.sourceTitle) — \(result.title)\n\(snippet)"
                        )
                    )
                    if excerpts.count >= limit {
                        return excerpts
                    }
                }
            }
        }
        return excerpts
    }
}
