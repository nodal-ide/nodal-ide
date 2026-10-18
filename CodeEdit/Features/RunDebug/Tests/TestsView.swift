//
//  TestsView.swift
//  CodeEdit
//
//  The Tests navigator: run test configurations and inspect results.
//

import SwiftUI

struct TestsView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let runner = workspace.testRunner {
            TestsContentView(runner: runner, workspace: workspace)
        } else {
            DebugEmptyState(systemImage: "checkmark.diamond", title: "No Tests", message: nil)
        }
    }
}

private struct TestSuiteGroup: Identifiable {
    let suite: String
    let results: [TestResult]
    var id: String { suite }
    var failed: Int { results.count { $0.status == .failed || $0.status == .error } }
}

private struct TestsContentView: View {
    @ObservedObject var runner: TestRunner
    let workspace: WorkspaceDocument

    @State private var search = ""
    @State private var failedOnly = false

    private var groups: [TestSuiteGroup] {
        Dictionary(grouping: runner.results, by: \.suite)
            .map { TestSuiteGroup(suite: $0.key, results: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.suite < $1.suite }
            .compactMap { group in
                let filtered = group.results.filter(matches)
                return filtered.isEmpty ? nil : TestSuiteGroup(suite: group.suite, results: filtered)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !runner.results.isEmpty {
                controls
                Divider()
                list
            } else {
                emptyState
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            DebugSearchField(text: $search)
            Spacer(minLength: 4)
            Button {
                failedOnly.toggle()
            } label: {
                Image(systemName: failedOnly ? "xmark.octagon.fill" : "xmark.octagon")
                    .foregroundStyle(failedOnly ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Show only failures")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(groups) { group in
                    TestSuiteGroupView(group: group) { open($0) }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func matches(_ result: TestResult) -> Bool {
        if failedOnly, result.status != .failed, result.status != .error { return false }
        if search.isEmpty { return true }
        return result.name.localizedCaseInsensitiveContains(search)
            || result.suite.localizedCaseInsensitiveContains(search)
    }

    @ViewBuilder private var emptyState: some View {
        if runner.isRunning {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Running tests…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !runner.rawOutput.isEmpty {
            rawOutputView
        } else if runner.configurations.isEmpty {
            DebugEmptyState(
                systemImage: "checkmark.diamond",
                title: "No Test Configuration",
                message: "Add a run configuration with kind “Test” (e.g. php forge.php test)."
            )
        } else {
            DebugEmptyState(
                systemImage: "checkmark.diamond",
                title: "No Results",
                message: "Press Run to execute your tests."
            )
        }
    }

    private var rawOutputView: some View {
        VStack(spacing: 0) {
            Text("Unrecognized output")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            Divider()
            ScrollView {
                Text(TestOutputParser.strippingANSI(runner.rawOutput))
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }

    private func open(_ result: TestResult) {
        guard let url = result.fileURL else { return }
        workspace.editorManager?.revealSourceLocation(url: url, line: result.line ?? 1)
    }
}

private struct TestSuiteGroupView: View {
    let group: TestSuiteGroup
    let onSelect: (TestResult) -> Void

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(group.results) { result in
                TestResultRow(result: result)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(result) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(group.suite)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if group.failed > 0 {
                    Text("\(group.failed)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                }
                Text("\(group.results.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .help(group.suite)
        }
        .padding(.horizontal, 8)
    }
}

private struct TestResultRow: View {
    let result: TestResult

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(result.name)
                .font(.system(size: 11))
                .foregroundStyle(isFailed ? .primary : .secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let duration = result.duration {
                Text(String(format: "%.0f ms", duration * 1000))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .background(hovering ? Color.secondary.opacity(0.08) : .clear)
        .onHover { hovering = $0 }
        .help(result.message ?? result.name)
    }

    private var isFailed: Bool { result.status == .failed || result.status == .error }

    private var icon: String {
        switch result.status {
        case .passed: return "checkmark.circle.fill"
        case .failed, .error: return "xmark.octagon.fill"
        case .skipped: return "minus.circle"
        }
    }

    private var color: Color {
        switch result.status {
        case .passed: return .green
        case .failed, .error: return .red
        case .skipped: return .secondary
        }
    }
}

// MARK: - Navigator bottom bar

struct TestsNavigatorToolbarBottom: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let runner = workspace.testRunner {
            TestsBottomBar(runner: runner)
        }
    }
}

private struct TestsBottomBar: View {
    @ObservedObject var runner: TestRunner

    var body: some View {
        HStack(spacing: 6) {
            Text(summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if runner.isRunning {
                ProgressView().controlSize(.small)
            }
            Button {
                runner.runFirst()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .disabled(runner.isRunning || runner.configurations.isEmpty)
            .help("Run tests")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var summary: String {
        if runner.isRunning { return "Running…" }
        if runner.results.isEmpty { return "No Results" }
        return "\(runner.passed) passed · \(runner.failed) failed"
    }
}
