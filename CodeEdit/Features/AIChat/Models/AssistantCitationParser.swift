import Foundation

enum AssistantCitationParser {
    static func citations(
        in text: String,
        items: [AssistantContextItem]
    ) -> [AssistantCitation] {
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var citations: [AssistantCitation] = []
        var seen = Set<String>()

        for match in matches(in: text) {
            guard let id = sourceID(from: match, in: text),
                  let item = itemsByID[id],
                  seen.insert(id).inserted
            else { continue }
            citations.append(citation(for: item))
        }
        return citations
    }

    static func removingKnownCitations(
        from text: String,
        citations: [AssistantCitation]
    ) -> String {
        let knownIDs = Set(citations.map(\.id))
        guard !knownIDs.isEmpty else { return text }
        var result = text

        for match in matches(in: text).reversed() {
            guard let id = sourceID(from: match, in: text),
                  knownIDs.contains(id),
                  let range = Range(match.range, in: result)
            else { continue }
            result.removeSubrange(range)
        }

        result = result.replacingOccurrences(
            of: "[ \\t]+([.,;:!?])",
            with: "$1",
            options: .regularExpression
        )
        return result.replacingOccurrences(
            of: "[ \\t]{2,}",
            with: " ",
            options: .regularExpression
        )
    }

    static func citation(for item: AssistantContextItem) -> AssistantCitation {
        AssistantCitation(
            id: item.id,
            title: item.title,
            relativePath: item.relativePath ?? "",
            line: item.lineRange?.lowerBound,
            endLine: item.lineRange?.upperBound,
            knowledgeSourceID: item.knowledgeSourceID
        )
    }

    private static func sourceID(from match: NSTextCheckingResult, in text: String) -> String? {
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func matches(in text: String) -> [NSTextCheckingResult] {
        guard let expression else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    private static let expression = try? NSRegularExpression(
        pattern: #"\[\[source:([A-Za-z0-9_-]+)\]\]"#
    )
}
