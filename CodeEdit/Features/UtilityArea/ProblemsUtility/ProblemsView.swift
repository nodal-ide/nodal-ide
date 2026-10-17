//
//  ProblemsView.swift
//  CodeEdit
//
//  The Utility Area Problems panel.
//

import AppKit
import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView

struct ProblemsView: View {
    @ObservedObject private var store = DiagnosticsStore.shared
    @EnvironmentObject private var workspace: WorkspaceDocument

    @State private var searchText = ""
    @State private var enabledSeverities: Set<EditorDiagnosticSeverity> = [.error, .warning, .info, .hint]
    @State private var groupByFile = true
    @State private var scope: Scope = .project

    enum Scope: String, CaseIterable, Identifiable {
        case project = "Project"
        case currentFile = "Current File"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(EditorDiagnosticSeverity.allCasesForProblems, id: \.self) { severity in
                    severityChip(severity)
                }
                Spacer(minLength: 4)
                Button {
                    rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Rescan project")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.plain)
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Button {
                    groupByFile.toggle()
                } label: {
                    Image(systemName: groupByFile ? "list.bullet" : "rectangle.grid.1x2")
                }
                .buttonStyle(.plain)
                .help(groupByFile ? "Show flat list" : "Group by file")
            }
        }
        .padding(10)
    }

    private func severityChip(_ severity: EditorDiagnosticSeverity) -> some View {
        let count = counts[severity] ?? 0
        let isEnabled = enabledSeverities.contains(severity)
        return Button {
            if isEnabled {
                enabledSeverities.remove(severity)
            } else {
                enabledSeverities.insert(severity)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: severity.problemIcon).font(.system(size: 10))
                Text("\(count)").font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isEnabled ? severity.problemColor : Color.secondary).opacity(0.15))
            .foregroundStyle(isEnabled ? severity.problemColor : Color.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Toggle \(severity.problemName) problems")
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if filtered.isEmpty {
                emptyState
            } else if groupByFile {
                groupedList
            } else {
                flatList
            }
        }
    }

    private var groupedList: some View {
        List {
            ForEach(groups, id: \.file) { group in
                Section {
                    ForEach(group.problems) { problem in
                        ProblemRow(problem: problem, showFile: false)
                            .contentShape(Rectangle())
                            .onTapGesture { open(problem) }
                            .contextMenu { contextMenu(problem) }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text(relativePath(group.file)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text("\(group.problems.count)").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11))
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var flatList: some View {
        List(filtered) { problem in
            ProblemRow(problem: problem, showFile: true)
                .contentShape(Rectangle())
                .onTapGesture { open(problem) }
                .contextMenu { contextMenu(problem) }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No problems detected" : "No matching problems")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(_ problem: EditorProblem) -> some View {
        Button("Open") { open(problem) }
        Button("Copy Message") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(problem.message, forType: .string)
        }
        if problem.ruleID != nil {
            Divider()
            Button("Ignore This Rule") { ignoreRule(problem) }
        }
    }

    // MARK: - Derived

    private var currentFileURL: URL? {
        workspace.editorManager?.activeEditor.selectedTab?.file.url
    }

    /// Problems in scope (ignores the severity filter so the chips show totals).
    private var scopedProblems: [EditorProblem] {
        var problems = workspace.fileURL.map { store.problems(in: $0) } ?? store.problems
        if scope == .currentFile, let current = currentFileURL {
            problems = problems.filter { $0.fileURL.standardizedFileURL == current.standardizedFileURL }
        }
        if !searchText.isEmpty {
            problems = problems.filter {
                $0.message.localizedCaseInsensitiveContains(searchText)
                    || $0.fileURL.lastPathComponent.localizedCaseInsensitiveContains(searchText)
            }
        }
        return problems
    }

    private var filtered: [EditorProblem] {
        scopedProblems.filter { enabledSeverities.contains($0.severity) }
    }

    private var counts: [EditorDiagnosticSeverity: Int] {
        scopedProblems.reduce(into: [:]) { counts, problem in
            counts[problem.severity, default: 0] += 1
        }
    }

    private var groups: [(file: URL, problems: [EditorProblem])] {
        Dictionary(grouping: filtered, by: \.fileURL)
            .map { (file: $0.key, problems: $0.value.sorted { ($0.line ?? 0) < ($1.line ?? 0) }) }
            .sorted { $0.file.path(percentEncoded: false) < $1.file.path(percentEncoded: false) }
    }

    private func relativePath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        if let root = workspace.fileURL?.path(percentEncoded: false), path.hasPrefix(root) {
            let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? url.lastPathComponent : relative
        }
        return url.lastPathComponent
    }

    // MARK: - Actions

    private func rescan() {
        guard let root = workspace.fileURL else { return }
        PHPWorkspaceIndex.shared.rescan(root: root)
    }

    private func open(_ problem: EditorProblem) {
        CodeEditDocumentController.shared.openDocument(
            withContentsOf: problem.fileURL,
            display: true
        ) { document, _, _ in
            guard let document = document as? CodeFileDocument else { return }
            var range = problem.range
            // Task problems only carry a line/column; compute the offset from the document.
            if range.location == 0, range.length == 0,
               let line = problem.line, let content = document.content?.string {
                let column = (problem.column ?? 1) - 1
                range = NSRange(
                    location: Self.offset(forLine: line - 1, column: column, in: content as NSString),
                    length: 0
                )
            }
            document.openOptions = .init(cursorPositions: [CursorPosition(range: range)])
        }
    }

    /// Inserts a `// @codeedit-ignore-next-line <rule>` comment above the problem.
    private func ignoreRule(_ problem: EditorProblem) {
        guard let ruleID = problem.ruleID else { return }
        CodeEditDocumentController.shared.openDocument(
            withContentsOf: problem.fileURL,
            display: true
        ) { document, _, _ in
            guard let document = document as? CodeFileDocument, let content = document.content else { return }
            let text = content.string as NSString
            let offset = Self.offset(forLine: (problem.line ?? 1) - 1, column: 0, in: text)
            let indent = Self.leadingWhitespace(in: text, at: offset)
            content.replaceCharacters(
                in: NSRange(location: offset, length: 0),
                with: "\(indent)// @codeedit-ignore-next-line \(ruleID)\n"
            )
            document.updateChangeCount(.changeDone)
        }
    }

    private static func offset(forLine line: Int, column: Int, in text: NSString) -> Int {
        var currentLine = 0
        var index = 0
        while index < text.length, currentLine < line {
            if text.character(at: index) == 0x0A {
                currentLine += 1
            }
            index += 1
        }
        return min(index + max(0, column), text.length)
    }

    private static func leadingWhitespace(in text: NSString, at offset: Int) -> String {
        var index = offset
        while index < text.length {
            let char = text.character(at: index)
            if char == 0x20 || char == 0x09 {
                index += 1
            } else {
                break
            }
        }
        return text.substring(with: NSRange(location: offset, length: index - offset))
    }
}

private struct ProblemRow: View {
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
