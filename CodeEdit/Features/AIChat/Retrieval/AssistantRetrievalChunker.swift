import Foundation

enum AssistantRetrievalChunker {
    static let maximumLines = 100
    static let overlapLines = 12
    static let maximumChunksPerWorkspace = 24_000

    static func chunks(
        text: String,
        relativePath: String,
        languageID: String
    ) -> [AssistantRetrievalChunk] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        var chunks: [AssistantRetrievalChunk] = []
        var start = 0

        while start < lines.count {
            let proposedEnd = min(start + maximumLines - 1, lines.count - 1)
            var end = proposedEnd

            if proposedEnd < lines.count - 1 {
                let minimumEnd = min(start + maximumLines / 2, proposedEnd)
                var candidate = proposedEnd
                while candidate >= minimumEnd {
                    if lines[candidate].trimmingCharacters(in: .whitespaces).isEmpty {
                        end = candidate
                        break
                    }
                    candidate -= 1
                }
            }

            let content = lines[start...end].joined(separator: "\n")
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let startLine = start + 1
                let endLine = end + 1
                chunks.append(
                    AssistantRetrievalChunk(
                        id: "\(relativePath):\(startLine)-\(endLine)",
                        relativePath: relativePath,
                        languageID: languageID,
                        startLine: startLine,
                        endLine: endLine,
                        contentHash: stableHash(content),
                        text: content
                    )
                )
            }

            guard end < lines.count - 1 else { break }
            let nextStart = max(start + 1, end + 1 - overlapLines)
            if nextStart <= start {
                start = end + 1
            } else {
                start = nextStart
            }
            if chunks.count >= maximumChunksPerWorkspace {
                break
            }
        }

        return chunks
    }

    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
