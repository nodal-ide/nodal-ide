//
//  TestsView.swift
//  CodeEdit
//
//  Minimal test runner view (Utility Area "Tests" tab).
//

import SwiftUI
import CodeEditSourceEditor

struct TestsView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        if let runner = workspace.testRunner {
            TestsContentView(runner: runner)
        } else {
            Text("No tests")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TestsContentView: View {
    @ObservedObject var runner: TestRunner
    @EnvironmentObject private var workspace: WorkspaceDocument

    private var groups: [(suite: String, results: [TestResult])] {
        Dictionary(grouping: runner.results, by: \.suite)
            .map { (suite: $0.key, results: $0.value) }
            .sorted { $0.suite < $1.suite }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if runner.results.isEmpty {
                Text(runner.isRunning ? "Running tests…" : "No test results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                runner.runFirst()
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Run the first test configuration")
            .disabled(runner.isRunning || runner.configurations.isEmpty)

            if runner.isRunning {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if !runner.results.isEmpty {
                Text("\(runner.passed) passed")
                    .foregroundStyle(.green)
                Text("\(runner.failed) failed")
                    .foregroundStyle(runner.failed > 0 ? .red : .secondary)
                Text("\(runner.skipped) skipped")
                    .foregroundStyle(.secondary)
            }
            if runner.configurations.isEmpty {
                Text("Add a Test run configuration")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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
