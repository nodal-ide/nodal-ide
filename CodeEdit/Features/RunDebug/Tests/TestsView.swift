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

private struct TestsContentView: View {
    @ObservedObject var runner: TestRunner
    let workspace: WorkspaceDocument

    private var groups: [(suite: String, results: [TestResult])] {
        Dictionary(grouping: runner.results, by: \.suite)
            .map { (suite: $0.key, results: $0.value) }
            .sorted { $0.suite < $1.suite }
    }

    var body: some View {
        Group {
            if runner.results.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(groups, id: \.suite) { group in
                        Section(group.suite) {
                            ForEach(group.results) { result in
                                TestResultRow(result: result)
                                    .contentShape(Rectangle())
                                    .onTapGesture { open(result) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if runner.isRunning {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Running tests…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !runner.rawOutput.isEmpty {
            DebugEmptyState(
                systemImage: "questionmark.circle",
                title: "No Parsed Results",
                message: "Tests ran, but the output wasn't in a recognized format (TAP/JUnit)."
            )
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

    private func open(_ result: TestResult) {
        guard let url = result.fileURL else { return }
        workspace.revealSourceLocation(url: url, line: result.line ?? 1)
    }
}

private struct TestResultRow: View {
    let result: TestResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(result.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let duration = result.duration {
                Text(String(format: "%.2fs", duration))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .help(result.message ?? result.name)
    }

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
