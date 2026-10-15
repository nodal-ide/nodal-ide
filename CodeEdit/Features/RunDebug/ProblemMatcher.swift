//
//  ProblemMatcher.swift
//  CodeEdit
//
//  Parses task/compiler output into problems for the Problems panel.
//

import Foundation
import CodeEditSourceEditor

/// A single problem extracted from task output.
struct TaskProblem: Identifiable {
    let id = UUID()
    let owner: String
    let fileURL: URL
    let line: Int
    let column: Int?
    let severity: EditorDiagnosticSeverity
    let message: String
}

/// One regex pattern with named capture groups (`file`, `line`, `column`, `severity`, `message`, `code`).
struct ProblemPattern {
    let regex: NSRegularExpression

    init(_ pattern: String) throws {
        self.regex = try NSRegularExpression(pattern: pattern)
    }

    private static let groupNames = ["file", "line", "column", "severity", "message", "code"]

    /// Returns the captured groups, or `nil` if the line doesn't match.
    func match(_ line: String) -> [String: String]? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let result = regex.firstMatch(in: line, range: range) else { return nil }
        var groups: [String: String] = [:]
        for name in Self.groupNames {
            let captured = result.range(withName: name)
            if captured.location != NSNotFound, let swiftRange = Range(captured, in: line) {
                groups[name] = String(line[swiftRange])
            }
        }
        return groups
    }
}

/// Matches task output lines to problems. Supports a single pattern or a two-pattern
/// (file line + detail line) form.
struct ProblemMatcher {
    let owner: String
    let name: String
    let patterns: [ProblemPattern]
    let severity: EditorDiagnosticSeverity

    /// A matcher for a known tool, or `nil` if `name` isn't recognized.
    static func preset(named name: String, owner: String? = nil) -> ProblemMatcher? {
        switch name {
        case "$gcc", "$clang":
            return make(
                name: "$gcc",
                owner: owner ?? "gcc",
                severity: .error,
                pattern: "^(?<file>.+?):(?<line>\\d+):(?<column>\\d+):\\s+"
                    + "(?<severity>error|warning|note|fatal error):\\s+(?<message>.+)$"
            )
        case "$tsc":
            return make(
                name: "$tsc",
                owner: owner ?? "tsc",
                severity: .error,
                pattern: "^(?<file>.+?)\\((?<line>\\d+),(?<column>\\d+)\\):\\s+"
                    + "(?<severity>error|warning)\\s+(?<code>TS\\d+):\\s+(?<message>.+)$"
            )
        default:
            return nil
        }
    }

    private static func make(
        name: String,
        owner: String,
        severity: EditorDiagnosticSeverity,
        pattern: String
    ) -> ProblemMatcher? {
        guard let compiled = try? ProblemPattern(pattern) else { return nil }
        return ProblemMatcher(owner: owner, name: name, patterns: [compiled], severity: severity)
    }
}

/// A streaming parser that feeds task output lines through a ``ProblemMatcher``.
final class ProblemMatcherParser {
    private let matcher: ProblemMatcher
    private let workingDirectory: URL
    private var pendingFileGroups: [String: String]?

    init(matcher: ProblemMatcher, workingDirectory: URL) {
        self.matcher = matcher
        self.workingDirectory = workingDirectory
    }

    /// Consumes a line of output and returns any problems it produced.
    func consume(_ line: String) -> [TaskProblem] {
        if matcher.patterns.count == 1 {
            guard let groups = matcher.patterns[0].match(line), let problem = makeProblem(groups) else {
                return []
            }
            return [problem]
        }

        let filePattern = matcher.patterns[0]
        let detailPattern = matcher.patterns[1]

        if let groups = filePattern.match(line), groups["file"] != nil {
            pendingFileGroups = groups
            return []
        }
        if let detail = detailPattern.match(line) {
            var combined = pendingFileGroups ?? [:]
            for (key, value) in detail { combined[key] = value }
            pendingFileGroups = nil
            return makeProblem(combined).map { [$0] } ?? []
        }
        return []
    }

    /// Signal the end of output (clears pending state).
    func finish() -> [TaskProblem] {
        pendingFileGroups = nil
        return []
    }

    private func makeProblem(_ groups: [String: String]) -> TaskProblem? {
        guard let file = groups["file"], !file.isEmpty,
              let line = groups["line"].flatMap(Int.init) else {
            return nil
        }
        return TaskProblem(
            owner: matcher.owner,
            fileURL: resolve(file),
            line: max(1, line),
            column: groups["column"].flatMap(Int.init).map { max(1, $0) },
            severity: severity(from: groups["severity"]),
            message: groups["message"] ?? groups["code"] ?? "Problem"
        )
    }

    private func severity(from value: String?) -> EditorDiagnosticSeverity {
        switch value?.lowercased() {
        case "error", "fatal error": return .error
        case "warning": return .warning
        case "note", "info", "information": return .info
        case "hint": return .hint
        default: return matcher.severity
        }
    }

    private func resolve(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(filePath: path) : URL(filePath: path, relativeTo: workingDirectory)
    }
}
