//
//  DiagnosticsStore.swift
//  CodeEdit
//
//  Native problems store for the Utility Area "Problems" tab.
//

import Foundation
import CodeEditSourceEditor

/// A single problem shown in the Problems panel.
struct EditorProblem: Identifiable {
    let id = UUID()
    let fileURL: URL
    let range: NSRange
    let line: Int?
    let column: Int?
    let severity: EditorDiagnosticSeverity
    let message: String

    init(
        fileURL: URL,
        range: NSRange,
        line: Int?,
        column: Int? = nil,
        severity: EditorDiagnosticSeverity,
        message: String
    ) {
        self.fileURL = fileURL
        self.range = range
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
    }
}

/// Collects native diagnostics for open files (and task output) so the Problems panel can list them.
@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published private(set) var problems: [EditorProblem] = []

    /// Language diagnostics, per file.
    private var byFile: [URL: [EditorProblem]] = [:]
    /// Task-output problems (from problem matchers), grouped by owner then file.
    private var byOwner: [String: [URL: [EditorProblem]]] = [:]

    private init() {}

    var errorCount: Int { problems.count { $0.severity == .error } }
    var warningCount: Int { problems.count { $0.severity == .warning } }

    func update(file: URL, diagnostics: [EditorDiagnostic]) {
        byFile[file] = diagnostics.map { diagnostic in
            EditorProblem(
                fileURL: file,
                range: diagnostic.range,
                line: diagnostic.line,
                severity: diagnostic.severity,
                message: diagnostic.message
            )
        }
        rebuild()
    }

    func clear(file: URL) {
        byFile[file] = nil
        rebuild()
    }

    /// Replaces all problems contributed by `owner` (e.g. a task run / problem matcher).
    func replaceProblems(owner: String, problems: [EditorProblem]) {
        var grouped: [URL: [EditorProblem]] = [:]
        for problem in problems {
            grouped[problem.fileURL, default: []].append(problem)
        }
        byOwner[owner] = grouped
        rebuild()
    }

    /// Removes all problems contributed by `owner`.
    func clear(owner: String) {
        byOwner[owner] = nil
        rebuild()
    }

    /// Problems for files that belong to the given workspace root.
    func problems(in root: URL) -> [EditorProblem] {
        let rootPath = root.path(percentEncoded: false)
        return problems.filter { Self.isInside($0.fileURL, rootPath: rootPath) }
    }

    /// Removes all diagnostics for files inside the given workspace root (called when a workspace closes).
    func clear(under root: URL) {
        let rootPath = root.path(percentEncoded: false)
        let removed = byFile.keys.filter { Self.isInside($0, rootPath: rootPath) }
        for key in removed {
            byFile[key] = nil
        }
        for owner in byOwner.keys {
            byOwner[owner] = byOwner[owner]?.filter { !Self.isInside($0.key, rootPath: rootPath) }
            if byOwner[owner]?.isEmpty == true {
                byOwner[owner] = nil
            }
        }
        guard !(removed.isEmpty && byOwner.isEmpty) else { return }
        rebuild()
    }

    private static func isInside(_ url: URL, rootPath: String) -> Bool {
        let path = url.path(percentEncoded: false)
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func rebuild() {
        let language = byFile.values.flatMap { $0 }
        let tasks = byOwner.values.flatMap { $0.values.flatMap { $0 } }
        problems = (language + tasks).sorted { lhs, rhs in
            if lhs.fileURL != rhs.fileURL { return lhs.fileURL.path < rhs.fileURL.path }
            return (lhs.line ?? 0) < (rhs.line ?? 0)
        }
    }
}
