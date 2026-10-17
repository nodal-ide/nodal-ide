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
    /// A stable rule id (e.g. `php.complexity`) when the source is rule-based.
    let ruleID: String?

    init(
        fileURL: URL,
        range: NSRange,
        line: Int?,
        column: Int? = nil,
        severity: EditorDiagnosticSeverity,
        message: String,
        ruleID: String? = nil
    ) {
        self.fileURL = fileURL
        self.range = range
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.ruleID = ruleID
    }
}

/// Collects native diagnostics for open files (and task output) so the Problems panel can list them.
@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published private(set) var problems: [EditorProblem] = []

    /// Increments whenever `problems` changes; used to debounce/cache derived UI state.
    @Published private(set) var revision = 0

    /// Language diagnostics, per file.
    private var byFile: [URL: [EditorProblem]] = [:]
    /// Task-output problems (from problem matchers), grouped by owner then file.
    private var byOwner: [String: [URL: [EditorProblem]]] = [:]

    private init() {}

    var errorCount: Int { problems.count { $0.severity == .error } }
    var warningCount: Int { problems.count { $0.severity == .warning } }

    func update(file: URL, diagnostics: [EditorDiagnostic]) {
        byFile[file] = diagnostics.map { problem(from: $0, file: file) }
        rebuild()
    }

    private func problem(from diagnostic: EditorDiagnostic, file: URL) -> EditorProblem {
        EditorProblem(
            fileURL: file,
            range: diagnostic.range,
            line: diagnostic.line,
            severity: diagnostic.severity,
            message: diagnostic.message,
            ruleID: diagnostic.ruleID
        )
    }

    /// Replaces the diagnostics for several files at once (one rebuild).
    func update(files: [URL: [EditorDiagnostic]]) {
        for (file, diagnostics) in files {
            byFile[file] = diagnostics.map { problem(from: $0, file: file) }
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
        // Normalize a trailing slash so a workspace URL like `…/project/` still matches its files.
        let root = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        return path == root || path.hasPrefix(root + "/")
    }

    private func rebuild() {
        let language = byFile.values.flatMap { $0 }
        let tasks = byOwner.values.flatMap { $0.values.flatMap { $0 } }
        problems = (language + tasks).sorted { lhs, rhs in
            if lhs.fileURL != rhs.fileURL { return lhs.fileURL.path < rhs.fileURL.path }
            return (lhs.line ?? 0) < (rhs.line ?? 0)
        }
        revision &+= 1
    }
}
