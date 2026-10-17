//
//  ProblemsView.swift
//  CodeEdit
//
//  The Problems navigator: filterable, grouped diagnostics.
//

import AppKit
import SwiftUI
import CodeEditSourceEditor

struct ProblemsView: View {
    @ObservedObject private var store = DiagnosticsStore.shared
    @EnvironmentObject private var workspace: WorkspaceDocument

    @State private var searchText = ""
    @State private var enabledSeverities: Set<EditorDiagnosticSeverity> = [.error, .warning, .info, .hint]
    @State private var groupByFile = true
    @State private var scope: Scope = .project

    @State private var groups: [ProblemGroup] = []
    @State private var flat: [EditorProblem] = []
    @State private var counts: [EditorDiagnosticSeverity: Int] = [:]
    @State private var total = 0
    @State private var hasLoaded = false

    static let maxRows = 2000

    enum Scope: String, CaseIterable, Identifiable {
        case project = "Project"
        case currentFile = "Current File"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .task(id: cacheKey) { await refresh() }
        .onAppear {
            // Show the previous derivation instantly when returning to the tab.
            if let cached = ProblemsResultsCache.shared.value(for: cacheKey) {
                apply(cached)
                hasLoaded = true
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                DebugSearchField(text: $searchText)
                Spacer(minLength: 4)
                scopeMenu
                groupToggle
            }
            HStack(spacing: 6) {
                ForEach(EditorDiagnosticSeverity.allCasesForProblems, id: \.self) { severity in
                    severityChip(severity)
                }
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var scopeMenu: some View {
        Picker("", selection: $scope) {
            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("Scope")
    }

    private var groupToggle: some View {
        Button {
            groupByFile.toggle()
        } label: {
            Image(systemName: groupByFile ? "rectangle.grid.1x2" : "list.bullet")
        }
        .buttonStyle(.plain)
        .help(groupByFile ? "Show flat list" : "Group by file")
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
            HStack(spacing: 3) {
                Image(systemName: severity.problemIcon).font(.system(size: 9))
                Text("\(count)").font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
            if !hasLoaded {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if flat.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if groupByFile {
                        groupedList
                    } else {
                        flatList
                    }
                    if total > Self.maxRows {
                        Divider()
                        Text("Showing first \(Self.maxRows) of \(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(6)
                    }
                }
            }
        }
    }

    private var groupedList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.problems) { problem in
                        row(problem, showFile: false)
                    }
                } header: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.file.lastPathComponent)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if !relativeDirectory(group.file).isEmpty {
                                Text(relativeDirectory(group.file))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 4)
                        Text("\(group.problems.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var flatList: some View {
        List(flat) { problem in
            row(problem, showFile: true)
        }
        .listStyle(.plain)
    }

    private func row(_ problem: EditorProblem, showFile: Bool) -> some View {
        ProblemRow(problem: problem, showFile: showFile)
            .contentShape(Rectangle())
            .onTapGesture { open(problem) }
            .contextMenu { contextMenu(problem) }
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
            Button("Ignore This Rule") { ProblemSuppression.ignoreRule(problem) }
        }
    }

    // MARK: - Derivation

    private var currentFileURL: URL? {
        workspace.editorManager?.activeEditor.selectedTab?.file.url
    }

    private var cacheKey: String {
        let severities = enabledSeverities.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
        let current = currentFileURL?.path(percentEncoded: false) ?? ""
        let root = workspace.fileURL?.path(percentEncoded: false) ?? ""
        return "\(store.revision)|\(searchText)|\(scope.rawValue)|\(groupByFile)|\(severities)|\(current)|\(root)"
    }

    private func refresh() async {
        // Debounce only after the first load (search/filter changes), not on the initial appearance.
        if hasLoaded {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
        }

        let snapshot = store.problems
        let query = ProblemsDerivation.Query(
            root: workspace.fileURL,
            currentFile: scope == .currentFile ? currentFileURL : nil,
            severities: enabledSeverities,
            search: searchText,
            groupByFile: groupByFile,
            maxRows: Self.maxRows
        )
        let output = await Task.detached(priority: .userInitiated) {
            ProblemsDerivation.derive(problems: snapshot, query: query)
        }.value
        guard !Task.isCancelled else { return }
        apply(output)
        hasLoaded = true
        ProblemsResultsCache.shared.set(output, for: cacheKey)
    }

    private func apply(_ output: ProblemsDerivation.Output) {
        groups = output.groups
        flat = output.flat
        counts = output.counts
        total = output.total
    }

}

private extension ProblemsView {
    private func relativePath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        if let root = workspace.fileURL?.path(percentEncoded: false), path.hasPrefix(root) {
            let relative = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? url.lastPathComponent : relative
        }
        return url.lastPathComponent
    }

    /// The directory portion of the relative path, for a group header's second line.
    private func relativeDirectory(_ url: URL) -> String {
        let relative = relativePath(url)
        guard let slash = relative.lastIndex(of: "/") else { return "" }
        return String(relative[..<slash])
    }

    /// Opens the problem's file and scrolls to its location.
    func open(_ problem: EditorProblem) {
        workspace.revealSourceLocation(
            url: problem.fileURL,
            line: problem.line ?? 1,
            column: problem.column ?? 1
        )
    }
}

// MARK: - Navigator bottom bar

struct ProblemsNavigatorToolbarBottom: View {
    @ObservedObject private var store = DiagnosticsStore.shared
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        HStack(spacing: 6) {
            Text(store.problems.isEmpty ? "No Problems" : "\(store.problems.count) Problems")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Rescan project")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func rescan() {
        guard let root = workspace.fileURL else { return }
        PHPWorkspaceIndex.shared.rescan(root: root)
    }
}
