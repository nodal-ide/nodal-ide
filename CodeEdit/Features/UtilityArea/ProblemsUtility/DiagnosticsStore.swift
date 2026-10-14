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
    let severity: EditorDiagnosticSeverity
    let message: String
}

/// Collects native diagnostics for open files so the Problems panel can list them.
@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published private(set) var problems: [EditorProblem] = []

    private var byFile: [URL: [EditorProblem]] = [:]

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

    /// Problems for files that belong to the given workspace root.
    func problems(in root: URL) -> [EditorProblem] {
        let rootPath = root.path(percentEncoded: false)
        return problems.filter { Self.isInside($0.fileURL, rootPath: rootPath) }
    }

    /// Removes all diagnostics for files inside the given workspace root (called when a workspace closes).
    func clear(under root: URL) {
        let rootPath = root.path(percentEncoded: false)
        let removed = byFile.keys.filter { Self.isInside($0, rootPath: rootPath) }
        guard !removed.isEmpty else { return }
        for key in removed {
            byFile[key] = nil
        }
        rebuild()
    }

    private static func isInside(_ url: URL, rootPath: String) -> Bool {
        let path = url.path(percentEncoded: false)
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func rebuild() {
        problems = byFile.values.flatMap { $0 }.sorted { lhs, rhs in
            if lhs.fileURL != rhs.fileURL { return lhs.fileURL.path < rhs.fileURL.path }
            return (lhs.line ?? 0) < (rhs.line ?? 0)
        }
    }
}