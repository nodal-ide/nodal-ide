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

    private func rebuild() {
        problems = byFile.values.flatMap { $0 }.sorted { lhs, rhs in
            if lhs.fileURL != rhs.fileURL { return lhs.fileURL.path < rhs.fileURL.path }
            return (lhs.line ?? 0) < (rhs.line ?? 0)
        }
    }
}