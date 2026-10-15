//
//  CEActiveTask.swift
//  CodeEditTests
//
//  Created by Tommy Ludwig on 24.06.24.
//

import SwiftUI
import Combine
import SwiftTerm

/// Stores the state of a task once it's executed
class CEActiveTask: ObservableObject, Identifiable, Hashable {
    /// The current progress of the task.
    @Published var output: CEActiveTaskTerminalView?

    var hasOutputBeenConfigured: Bool = false

    /// The status of the task.
    @Published private(set) var status: CETaskStatus = .notRunning

    /// The name of the associated task.
    @ObservedObject var task: CETask

    /// Prevents tasks overwriting each other.
    /// Say a user cancels one task, then runs it immediately, the cancel message should show and then the
    /// starting message should show. If we don't add this modifier the starting message will be deleted.
    var activeTaskID: UUID = UUID()

    var taskId: String {
        task.id.uuidString + "-" + activeTaskID.uuidString
    }

    var workspaceURL: URL?

    private var cancellables = Set<AnyCancellable>()

    init(task: CETask) {
        self.task = task

        self.task.objectWillChange.sink { _ in
            self.objectWillChange.send()
        }.store(in: &cancellables)
    }

    @MainActor
    func run(workspaceURL: URL?, shell: Shell? = nil) {
        self.workspaceURL = workspaceURL
        self.activeTaskID = UUID() // generate a new ID for this run

        createStatusTaskNotification()
        updateTaskStatus(to: .running)

        let view = output ?? CEActiveTaskTerminalView(activeTask: self)
        installOutputTap(view: view)
        configureMatcher(workspaceURL: workspaceURL)
        view.startProcess(workspaceURL: workspaceURL, shell: shell)

        output = view
    }

    // MARK: - Output & problem matchers

    private var matcherParser: ProblemMatcherParser?
    private var matcherProblems: [TaskProblem] = []
    private var outputLineBuffer = ""

    /// Owner key for this task's problems in the Problems panel.
    private var matcherOwner: String { "task:\(task.id.uuidString)" }

    @MainActor
    private func installOutputTap(view: CEActiveTaskTerminalView) {
        view.outputTap = { [weak self] slice in
            guard let text = String(bytes: slice, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.handleOutput(text)
            }
        }
    }

    @MainActor
    private func configureMatcher(workspaceURL: URL?) {
        guard let name = task.problemMatcher,
              let matcher = ProblemMatcher.preset(named: name),
              let workingDirectory = workspaceURL else {
            return
        }
        DiagnosticsStore.shared.clear(owner: matcherOwner)
        matcherProblems = []
        outputLineBuffer = ""
        matcherParser = ProblemMatcherParser(matcher: matcher, workingDirectory: workingDirectory)
    }

    @MainActor
    private func handleOutput(_ text: String) {
        task.outputObserver?(text)

        guard matcherParser != nil else { return }
        outputLineBuffer += text
        while let newline = outputLineBuffer.firstIndex(of: "\n") {
            let line = String(outputLineBuffer[..<newline])
            outputLineBuffer = String(outputLineBuffer[outputLineBuffer.index(after: newline)...])

            let found = matcherParser?.consume(line) ?? []
            guard !found.isEmpty else { continue }
            matcherProblems.append(contentsOf: found)
            DiagnosticsStore.shared.replaceProblems(
                owner: matcherOwner,
                problems: matcherProblems.map(Self.editorProblem)
            )
        }
    }

    private static func editorProblem(_ problem: TaskProblem) -> EditorProblem {
        EditorProblem(
            fileURL: problem.fileURL,
            range: NSRange(location: 0, length: 0),
            line: problem.line,
            column: problem.column,
            severity: problem.severity,
            message: problem.message
        )
    }

    @MainActor
    func handleProcessFinished(terminationStatus: Int32) {
        // Shells add 128 to non-zero exit codes.
        var terminationStatus = terminationStatus
        if terminationStatus > 128 {
            terminationStatus -= 128
        }

        switch terminationStatus {
        case 0:
            output?.newline()
            output?.sendOutputMessage("Finished running \(task.name).")
            output?.newline()

            updateTaskStatus(to: .finished)
            updateTaskNotification(
                title: "Finished Running \(task.name)",
                message: "",
                isLoading: false
            )
        case 2, 15: // SIGINT or SIGTERM
            output?.newline()
            output?.sendOutputMessage("\(task.name) cancelled.")
            output?.newline()

            updateTaskStatus(to: .notRunning)
            updateTaskNotification(
                title: "\(task.name) cancelled",
                message: "",
                isLoading: false
            )
        case 17: // SIGSTOP
            updateTaskStatus(to: .stopped)
        default:
            output?.newline()
            output?.sendOutputMessage("Failed to run \(task.name)")
            output?.newline()

            updateTaskStatus(to: .failed)
            updateTaskNotification(
                title: "Failed Running \(task.name)",
                message: "",
                isLoading: false
            )
        }

        deleteStatusTaskNotification()
        task.onFinish?()
    }

    @MainActor
    func suspend() {
        if let shellPID = output?.runningPID(), status == .running {
            kill(shellPID, SIGSTOP)
            updateTaskStatus(to: .stopped)
        }
    }

    @MainActor
    func resume() {
        if let shellPID = output?.runningPID(), status == .running {
            kill(shellPID, SIGCONT)
            updateTaskStatus(to: .running)
        }
    }

    func terminate() {
        if let shellPID = output?.runningPID() {
            kill(shellPID, SIGTERM)
        }
    }

    func interrupt() {
        if let shellPID = output?.runningPID() {
            kill(shellPID, SIGINT)
        }
    }

    func waitForExit() {
        if let shellPID = output?.runningPID() {
            waitid(P_PGID, UInt32(shellPID), nil, 0)
        }
    }

    @MainActor
    func clearOutput() {
        output?.terminal.resetToInitialState()
        output?.feed(text: "")
    }

    private func createStatusTaskNotification() {
        let userInfo: [String: Any] = [
            "id": taskId,
            "action": "createWithPriority",
            "title": "Running \(self.task.name)",
            "message": "Running your task: \(self.task.name).",
            "isLoading": true,
            "workspace": workspaceURL as Any
        ]

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
    }

    private func deleteStatusTaskNotification() {
        let deleteInfo: [String: Any] = [
            "id": taskId,
            "action": "deleteWithDelay",
            "delay": 3.0,
            "workspace": workspaceURL as Any
        ]

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: deleteInfo)
    }

    private func updateTaskNotification(title: String? = nil, message: String? = nil, isLoading: Bool? = nil) {
        var userInfo: [String: Any] = [
            "id": taskId,
            "action": "update",
            "workspace": workspaceURL as Any
        ]
        if let title {
            userInfo["title"] = title
        }
        if let message {
            userInfo["message"] = message
        }
        if let isLoading {
            userInfo["isLoading"] = isLoading
        }

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
    }

    @MainActor
    func updateTaskStatus(to taskStatus: CETaskStatus) {
        self.status = taskStatus
    }

    static func == (lhs: CEActiveTask, rhs: CEActiveTask) -> Bool {
        return lhs.output == rhs.output &&
        lhs.status == rhs.status &&
        lhs.output?.process.shellPid == rhs.output?.process.shellPid &&
        lhs.task == rhs.task
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(output)
        hasher.combine(status)
        hasher.combine(task)
    }
}
