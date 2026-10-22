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
    let languageContext: LanguageZoneContext?

    init(
        fileURL: URL,
        range: NSRange,
        line: Int?,
        column: Int? = nil,
        severity: EditorDiagnosticSeverity,
        message: String,
        ruleID: String? = nil,
        languageContext: LanguageZoneContext? = nil
    ) {
        self.fileURL = fileURL
        self.range = range
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.ruleID = ruleID
        self.languageContext = languageContext
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
    /// A cheap content signature per file so identical re-publishes don't trigger a rebuild.
    private var byFileSignature: [URL: Int] = [:]
    /// Task-output problems (from problem matchers), grouped by owner then file.
    private var byOwner: [String: [URL: [EditorProblem]]] = [:]

    private var cachedErrorCount = 0
    private var cachedWarningCount = 0

    private init() {}

    var errorCount: Int { cachedErrorCount }
    var warningCount: Int { cachedWarningCount }

    func update(file: URL, diagnostics: [EditorDiagnostic]) {
        let signature = Self.signature(of: diagnostics)
        guard byFileSignature[file] != signature else { return }
        byFileSignature[file] = signature
        byFile[file] = diagnostics.isEmpty ? nil : diagnostics.map { problem(from: $0, file: file) }
        rebuild()
    }

    private func problem(from diagnostic: EditorDiagnostic, file: URL) -> EditorProblem {
        EditorProblem(
            fileURL: file,
            range: diagnostic.range,
            line: diagnostic.line,
            severity: diagnostic.severity,
            message: diagnostic.message,
            ruleID: diagnostic.ruleID,
            languageContext: diagnostic.languageContext
        )
    }

    /// Replaces the diagnostics for several files at once (one rebuild when anything changed).
    func update(files: [URL: [EditorDiagnostic]]) {
        var changed = false
        for (file, diagnostics) in files {
            let signature = Self.signature(of: diagnostics)
            guard byFileSignature[file] != signature else { continue }
            byFileSignature[file] = signature
            byFile[file] = diagnostics.isEmpty ? nil : diagnostics.map { problem(from: $0, file: file) }
            changed = true
        }
        if changed { rebuild() }
    }

    func clear(file: URL) {
        guard byFile[file] != nil || byFileSignature[file] != nil else { return }
        byFile[file] = nil
        byFileSignature[file] = nil
        rebuild()
    }

    /// A content hash for a file's diagnostics (ignores object identity) to detect no-op updates.
    private static func signature(of diagnostics: [EditorDiagnostic]) -> Int {
        var hasher = Hasher()
        hasher.combine(diagnostics.count)
        for diagnostic in diagnostics {
            hasher.combine(diagnostic.range.location)
            hasher.combine(diagnostic.range.length)
            hasher.combine(diagnostic.line)
            hasher.combine(diagnostic.message)
            hasher.combine(diagnostic.severity.rawValue)
            hasher.combine(diagnostic.ruleID)
            hasher.combine(diagnostic.languageContext?.languageID.rawValue)
            hasher.combine(diagnostic.languageContext?.parentLanguageID?.rawValue)
            hasher.combine(diagnostic.languageContext?.sourceKey)
            hasher.combine(diagnostic.languageContext?.depth)
            hasher.combine(diagnostic.languageContext?.range?.location)
            hasher.combine(diagnostic.languageContext?.range?.length)
        }
        return hasher.finalize()
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
            byFileSignature[key] = nil
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
        let merged = (language + tasks).sorted { lhs, rhs in
            if lhs.fileURL != rhs.fileURL { return lhs.fileURL.path < rhs.fileURL.path }
            return (lhs.line ?? 0) < (rhs.line ?? 0)
        }
        var errors = 0
        var warnings = 0
        for problem in merged {
            switch problem.severity {
            case .error: errors += 1
            case .warning: warnings += 1
            default: break
            }
        }
        problems = merged
        cachedErrorCount = errors
        cachedWarningCount = warnings
        revision &+= 1
    }
}
