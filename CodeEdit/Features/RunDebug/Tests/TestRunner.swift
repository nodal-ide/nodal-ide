//
//  TestRunner.swift
//  CodeEdit
//
//  Runs test configurations and parses their output into results.
//

import Combine
import Foundation

@MainActor
final class TestRunner: ObservableObject {
    private weak var workspace: WorkspaceDocument?

    @Published private(set) var results: [TestResult] = []
    @Published private(set) var rawOutput = ""
    @Published private(set) var isRunning = false

    private var outputBuffer = ""
    private let owner = "tests"

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    /// Test-kind run configurations.
    var configurations: [RunConfiguration] {
        (workspace?.runConfigurationStore?.configurations ?? []).filter { $0.kind == .test }
    }

    var passed: Int { results.count { $0.status == .passed } }
    var failed: Int { results.count { $0.status == .failed || $0.status == .error } }
    var skipped: Int { results.count { $0.status == .skipped } }

    func run(_ configuration: RunConfiguration) {
        guard let taskManager = workspace?.taskManager else { return }
        results = []
        rawOutput = ""
        outputBuffer = ""
        isRunning = true
        AppServices.diagnosticsStore.clear(owner: owner)

        let task = CETask(
            name: configuration.name,
            target: "",
            workingDirectory: configuration.workingDirectory,
            command: configuration.command,
            environmentVariables: configuration.environment.map {
                CETask.EnvironmentVariable(key: $0.key, value: $0.value)
            }
        )
        task.outputObserver = { [weak self] text in
            self?.outputBuffer += text
        }
        task.onFinish = { [weak self] in
            self?.finish()
        }
        taskManager.taskShowingOutput = task.id
        Task { await taskManager.runTask(task: task) }
    }

    func runFirst() {
        guard let configuration = configurations.first else { return }
        run(configuration)
    }

    @MainActor
    private func finish() {
        rawOutput = outputBuffer
        results = TestOutputParser.parse(outputBuffer)
        isRunning = false

        let failures = results.filter { $0.status == .failed || $0.status == .error }
        AppServices.diagnosticsStore.replaceProblems(
            owner: owner,
            problems: failures.compactMap { result in
                guard let url = result.fileURL else { return nil }
                let message = "\(result.suite) › \(result.name)"
                    + (result.message.map { ": \($0)" } ?? "")
                return EditorProblem(
                    fileURL: url,
                    range: NSRange(location: 0, length: 0),
                    line: result.line,
                    column: nil,
                    severity: .error,
                    message: message
                )
            }
        )
    }
}
