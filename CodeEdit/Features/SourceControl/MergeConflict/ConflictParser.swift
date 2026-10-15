//
//  ConflictParser.swift
//  CodeEdit
//
//  Parses git conflict markers from file content.
//

import Foundation

enum ConflictParser {
    /// Parses conflict markers (`<<<<<<<` / `|||||||` / `=======` / `>>>>>>>`) from file content.
    static func parse(_ content: String) -> ConflictFile {
        let lines = linesWithRanges(in: content)

        var conflicts: [ConflictBlock] = []
        var index = 0

        while index < lines.count {
            guard lines[index].text.hasPrefix("<<<<<<<") else {
                index += 1
                continue
            }

            let startIndex = index
            let oursLabel = String(lines[index].text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)

            var ours = ""
            var theirs = ""
            var base: String?
            // 0 = ours, 1 = base, 2 = theirs
            var section = 0
            var endIndex: Int?
            var theirsLabel = ""

            var cursor = index + 1
            while cursor < lines.count {
                let line = lines[cursor].text
                if line.hasPrefix("|||||||") {
                    base = ""
                    section = 1
                } else if line.hasPrefix("=======") {
                    section = 2
                } else if line.hasPrefix(">>>>>>>") {
                    theirsLabel = String(line.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                    endIndex = cursor
                    break
                } else {
                    switch section {
                    case 0: ours += line
                    case 1: base = (base ?? "") + line
                    default: theirs += line
                    }
                }
                cursor += 1
            }

            if let endIndex {
                let range = NSRange(
                    location: lines[startIndex].range.location,
                    length: NSMaxRange(lines[endIndex].range) - lines[startIndex].range.location
                )
                conflicts.append(
                    ConflictBlock(
                        range: range,
                        ours: ours,
                        theirs: theirs,
                        base: base,
                        oursLabel: oursLabel,
                        theirsLabel: theirsLabel
                    )
                )
                index = endIndex + 1
            } else {
                index += 1
            }
        }

        return ConflictFile(content: content, conflicts: conflicts)
    }

    /// Splits the content into lines, each with its range (including the line terminator).
    private static func linesWithRanges(in content: String) -> [(range: NSRange, text: String)] {
        let ns = content as NSString
        var result: [(range: NSRange, text: String)] = []
        var index = 0
        while index < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            guard lineRange.length > 0 else { break }
            result.append((lineRange, ns.substring(with: lineRange)))
            index = NSMaxRange(lineRange)
        }
        return result
    }
}
