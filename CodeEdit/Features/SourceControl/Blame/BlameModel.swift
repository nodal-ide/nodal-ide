//
//  BlameModel.swift
//  CodeEdit
//
//  Models for parsed `git blame` output.
//

import Foundation

/// Blame information for a single (final) line of a file.
struct BlameLine: Identifiable, Hashable {
    let id = UUID()
    /// The abbreviated commit hash.
    let commitHash: String
    let author: String
    let authorDate: Date?
    let summary: String
    /// The 1-based line number in the current file.
    let lineNumber: Int
    /// The line's text.
    let text: String
}

enum BlameParser {
    /// Parses `git blame --line-porcelain` output.
    static func parse(_ output: String) -> [BlameLine] {
        var result: [BlameLine] = []

        var hash = ""
        var author = ""
        var authorTime: TimeInterval?
        var summary = ""
        var lineNumber = 0
        var haveHeader = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("\t") {
                // The source line content — finalizes the current entry.
                guard haveHeader else { continue }
                let date = authorTime.map { Date(timeIntervalSince1970: $0) }
                result.append(
                    BlameLine(
                        commitHash: String(hash.prefix(8)),
                        author: author,
                        authorDate: date,
                        summary: summary,
                        lineNumber: lineNumber,
                        text: String(line.dropFirst())
                    )
                )
                haveHeader = false
                continue
            }

            if let header = parseHeader(line) {
                hash = header.hash
                lineNumber = header.finalLine
                author = ""
                authorTime = nil
                summary = ""
                haveHeader = true
            } else if line.hasPrefix("author ") {
                author = String(line.dropFirst("author ".count))
            } else if line.hasPrefix("author-time ") {
                authorTime = TimeInterval(String(line.dropFirst("author-time ".count)))
            } else if line.hasPrefix("summary ") {
                summary = String(line.dropFirst("summary ".count))
            }
        }

        return result
    }

    /// Parses a `<sha> <orig-line> <final-line> <num-lines>` header line.
    private static func parseHeader(_ line: String) -> (hash: String, finalLine: Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3,
              parts[0].count == 40,
              parts[0].allSatisfy({ $0.isHexDigit }),
              let finalLine = Int(parts[2]) else {
            return nil
        }
        return (String(parts[0]), finalLine)
    }
}
