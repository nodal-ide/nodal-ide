//
//  DiffModel.swift
//  CodeEdit
//
//  Models for a parsed unified diff (used by the diff viewer).
//

import Foundation

/// A single line in a diff hunk.
struct DiffLine: Identifiable, Hashable {
    enum Kind {
        case context
        case addition
        case deletion
    }

    let id = UUID()
    let kind: Kind
    /// The line's text, without the leading `+`/`-`/space marker.
    let text: String
    /// The 1-based line number in the old file (nil for additions).
    let oldLineNumber: Int?
    /// The 1-based line number in the new file (nil for deletions).
    let newLineNumber: Int?
}

/// A contiguous block of changes with a `@@` header.
struct DiffHunk: Identifiable, Hashable {
    let id = UUID()
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]

    var header: String {
        "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
    }
}

/// A parsed diff for a single file.
struct FileDiff: Hashable {
    let oldPath: String?
    let newPath: String?
    /// The file header (`diff --git`, `index`, `---`, `+++`), needed to build applyable patches.
    let header: String
    let hunks: [DiffHunk]

    var isEmpty: Bool { hunks.isEmpty }
    var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count } }
    var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count } }

    /// Builds a `git apply`-able patch for a single hunk.
    func patch(for hunk: DiffHunk) -> String {
        header + hunk.patchText
    }
}

extension DiffHunk {
    /// The hunk rendered as unified-diff text (header + prefixed lines).
    var patchText: String {
        var result = header + "\n"
        for line in lines {
            switch line.kind {
            case .addition: result += "+" + line.text + "\n"
            case .deletion: result += "-" + line.text + "\n"
            case .context: result += " " + line.text + "\n"
            }
        }
        return result
    }
}
