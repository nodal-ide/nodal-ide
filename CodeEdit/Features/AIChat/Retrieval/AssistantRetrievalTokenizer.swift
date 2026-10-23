import Foundation

enum AssistantRetrievalTokenizer {
    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "can", "do", "does", "for",
        "from", "how", "i", "if", "in", "is", "it", "of", "on", "or", "should", "that",
        "the", "this", "to", "was", "we", "what", "when", "where", "which", "why", "with",
        "would", "you"
    ]

    static func terms(in text: String) -> [String] {
        guard let identifierExpression else { return [] }
        let identifiers = identifierExpression
            .matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
            .compactMap { match -> String? in
                guard let range = Range(match.range, in: text) else { return nil }
                let value = String(text[range])
                guard !value.isEmpty else { return nil }
                return value
            }

        var result: [String] = []
        for identifier in identifiers {
            let pieces = splitIdentifier(identifier)
            for piece in pieces {
                let normalized = piece.lowercased()
                guard normalized.count >= 2,
                      !stopWords.contains(normalized),
                      normalized.rangeOfCharacter(from: .letters.union(.decimalDigits)) != nil
                else { continue }
                result.append(normalized)
            }
        }
        return result
    }

    static func termFrequencies(in text: String) -> [String: Int] {
        var frequencies: [String: Int] = [:]
        for term in terms(in: text) {
            frequencies[term, default: 0] += 1
        }
        return frequencies
    }

    static func weightedTerms(in text: String, weight: Double) -> [String: Double] {
        var result: [String: Double] = [:]
        for term in terms(in: text) {
            result[term, default: 0] += weight
        }
        return result
    }

    private static func splitIdentifier(_ identifier: String) -> [String] {
        var pieces: [String] = []
        for underscored in identifier.split(separator: "_") {
            let value = String(underscored)
            guard !value.isEmpty else { continue }
            let camelParts = value
                .replacingOccurrences(
                    of: "([A-Z]+)([A-Z][a-z])",
                    with: "$1 $2",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: "([a-z0-9])([A-Z])",
                    with: "$1 $2",
                    options: .regularExpression
                )
                .split(separator: " ")
                .map(String.init)
            if camelParts.isEmpty {
                pieces.append(value)
            } else {
                pieces.append(contentsOf: camelParts)
            }
        }
        return pieces
    }

    private static let identifierExpression = try? NSRegularExpression(pattern: "[A-Za-z0-9_]+")
}
