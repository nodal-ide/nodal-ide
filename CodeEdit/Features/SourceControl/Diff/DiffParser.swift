//
//  DiffParser.swift
//  CodeEdit
//
//  Parses unified diff output into ``FileDiff``.
//

import Foundation

enum DiffParser {
    /// Parses unified diff text (as produced by `git diff`) into a ``FileDiff``.
    ///
    /// Only the first file in the diff is returned; pass a single-file diff when multiple files are possible.
    static func parse(_ diff: String) -> FileDiff {
        var oldPath: String?
        var newPath: String?
        var hunks: [DiffHunk] = []

        var currentLines: [DiffLine] = []
        var hunkOldStart = 0
        var hunkOldCount = 0
        var hunkNewStart = 0
        var hunkNewCount = 0
        var oldLine = 0
        var newLine = 0

        func flushHunk() {
            guard !currentLines.isEmpty || hunkOldCount > 0 || hunkNewCount > 0 else { return }
            hunks.append(
                DiffHunk(
                    oldStart: hunkOldStart,
                    oldCount: hunkOldCount,
                    newStart: hunkNewStart,
                    newCount: hunkNewCount,
                    lines: currentLines
                )
            )
            currentLines = []
        }

        for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("@@") {
                flushHunk()
                if let header = parseHunkHeader(line) {
                    hunkOldStart = header.oldStart
                    hunkOldCount = header.oldCount
                    hunkNewStart = header.newStart
                    hunkNewCount = header.newCount
                    oldLine = header.oldStart
                    newLine = header.newStart
                }
            } else if line.hasPrefix("--- ") {
                oldPath = String(line.dropFirst(4))
            } else if line.hasPrefix("+++ ") {
                newPath = String(line.dropFirst(4))
            } else if line.hasPrefix("+") {
                currentLines.append(
                    DiffLine(kind: .addition, text: String(line.dropFirst()), oldLineNumber: nil, newLineNumber: newLine)
                )
                newLine += 1
            } else if line.hasPrefix("-") {
                currentLines.append(
                    DiffLine(kind: .deletion, text: String(line.dropFirst()), oldLineNumber: oldLine, newLineNumber: nil)
                )
                oldLine += 1
            } else if line.hasPrefix(" ") {
                currentLines.append(
                    DiffLine(
                        kind: .context,
                        text: String(line.dropFirst()),
                        oldLineNumber: oldLine,
                        newLineNumber: newLine
                    )
                )
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — ignore.
                continue
            }
        }
        flushHunk()

        return FileDiff(oldPath: stripPrefix(oldPath), newPath: stripPrefix(newPath), hunks: hunks)
    }

    /// Strips the leading `a/`/`b/` and any tab-suffix from a diff path.
    private static func stripPrefix(_ path: String?) -> String? {
        guard var path else { return nil }
        if path == "/dev/null" { return path }
        if let tab = path.firstIndex(of: "\t") {
            path = String(path[..<tab])
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        return path
    }

    private struct HunkHeader {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    private static func parseHunkHeader(_ line: String) -> HunkHeader? {
        // @@ -a,b +c,d @@
        let pattern = "^@@ -(\\d+)(?:,(\\d+))? \\+(\\d+)(?:,(\\d+))? @@"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else {
            return nil
        }

        func group(_ index: Int) -> Int? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else { return nil }
            return Int(line[swiftRange])
        }

        guard let oldStart = group(1), let newStart = group(3) else { return nil }
        return HunkHeader(oldStart: oldStart, oldCount: group(2) ?? 1, newStart: newStart, newCount: group(4) ?? 1)
    }
}
