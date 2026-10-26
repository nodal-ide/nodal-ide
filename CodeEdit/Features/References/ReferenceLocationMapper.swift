import Foundation
import CodeEditLang

enum ReferenceLocationMapper {
    struct LocationRef: Sendable, Hashable {
        let uri: String
        let startLine: Int
        let startCharacter: Int
        let endLine: Int
        let endCharacter: Int
    }

    static func outcome(
        for locations: [LocationRef],
        textProvider: any SourceTextProviding,
        limit: Int
    ) -> ReferenceQueryOutcome {
        guard !locations.isEmpty else { return .results([], isComplete: true) }
        guard limit > 0 else { return .results([], isComplete: false) }

        var order: [String] = []
        var grouped: [String: [LocationRef]] = [:]
        for location in locations {
            if grouped[location.uri] == nil { order.append(location.uri) }
            grouped[location.uri, default: []].append(location)
        }

        var results: [EditorReference] = []
        var seen = Set<String>()
        var isComplete = true

        for uri in order {
            guard let url = URL(string: uri), url.isFileURL else { continue }
            let fileURL = url.standardizedFileURL
            guard let text = textProvider.text(for: fileURL) else {
                isComplete = false
                continue
            }
            let index = SourceLineIndex(text)
            for location in grouped[uri] ?? [] {
                guard let range = nsRange(for: location, in: index),
                      let reference = index.reference(for: range, in: text, fileURL: fileURL),
                      seen.insert(reference.id).inserted else {
                    continue
                }
                results.append(reference)
                if results.count >= limit {
                    return .results(results, isComplete: false)
                }
            }
        }

        return .results(results, isComplete: isComplete)
    }

    static func position(forOffset offset: Int, in text: String) -> (line: Int, character: Int)? {
        guard let position = SourceLineIndex(text).position(atOffset: offset) else { return nil }
        return (position.line, position.column)
    }

    private static func nsRange(for location: LocationRef, in index: SourceLineIndex) -> NSRange? {
        guard let start = index.offset(line: location.startLine, column: location.startCharacter),
              let end = index.offset(line: location.endLine, column: location.endCharacter),
              end >= start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }
}
