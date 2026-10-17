//
//  ProblemsSupport.swift
//  CodeEdit
//
//  Supporting types for the Problems panel.
//

import SwiftUI
import CodeEditSourceEditor

/// Problems grouped under one file (for the grouped list).
struct ProblemGroup: Identifiable, Sendable {
    let file: URL
    let problems: [EditorProblem]
    var id: URL { file }
}

/// Pure, off-main-thread derivation of the panel's displayed data.
enum ProblemsDerivation {
    struct Query: Sendable {
        var root: URL?
        var currentFile: URL?
        var severities: Set<EditorDiagnosticSeverity>
        var search: String
        var groupByFile: Bool
        var maxRows: Int
    }

    struct Output: Sendable {
        var groups: [ProblemGroup]
        var flat: [EditorProblem]
        var counts: [EditorDiagnosticSeverity: Int]
        var total: Int
    }

    static func derive(problems: [EditorProblem], query: Query) -> Output {
        var scoped = problems
        if let rootPath = query.root?.path(percentEncoded: false) {
            let root = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
            scoped = problems.filter {
                let path = $0.fileURL.path(percentEncoded: false)
                return path == root || path.hasPrefix(root + "/")
            }
        }
        if let currentFile = query.currentFile {
            let current = currentFile.standardizedFileURL
            scoped = scoped.filter { $0.fileURL.standardizedFileURL == current }
        }
        if !query.search.isEmpty {
            scoped = scoped.filter {
                $0.message.localizedCaseInsensitiveContains(query.search)
                    || $0.fileURL.lastPathComponent.localizedCaseInsensitiveContains(query.search)
            }
        }

        var counts: [EditorDiagnosticSeverity: Int] = [:]
        for problem in scoped {
            counts[problem.severity, default: 0] += 1
        }

        let shown = scoped.filter { query.severities.contains($0.severity) }
        let total = shown.count
        let capped = total > query.maxRows ? Array(shown.prefix(query.maxRows)) : shown

        var groups: [ProblemGroup] = []
        if query.groupByFile {
            groups = Dictionary(grouping: capped, by: \.fileURL)
                .map { ProblemGroup(
                    file: $0.key,
                    problems: $0.value.sorted { ($0.line ?? 0) < ($1.line ?? 0) }
                ) }
                .sorted { $0.file.path(percentEncoded: false) < $1.file.path(percentEncoded: false) }
        }
        return Output(groups: groups, flat: capped, counts: counts, total: total)
    }
}

struct ProblemRow: View {
    let problem: EditorProblem
    let showFile: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: problem.severity.problemIcon)
                .foregroundStyle(problem.severity.problemColor)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(problem.message)
                    .font(.system(size: 12))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showFile {
            parts.append(problem.fileURL.lastPathComponent)
        }
        if let line = problem.line {
            parts.append("line \(line)")
        }
        return parts.joined(separator: " · ")
    }
}

extension EditorDiagnosticSeverity {
    static var allCasesForProblems: [EditorDiagnosticSeverity] { [.error, .warning, .info, .hint] }

    var problemName: String {
        switch self {
        case .error: return "errors"
        case .warning: return "warnings"
        case .info: return "info"
        case .hint: return "hints"
        }
    }

    var problemIcon: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        }
    }

    var problemColor: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .hint: return .secondary
        }
    }
}
