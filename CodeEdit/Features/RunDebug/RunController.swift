//
//  RunController.swift
//  CodeEdit
//
//  Runs and stops run configurations (via the task runner).
//

import Combine
import Foundation

@MainActor
final class RunController: ObservableObject {
    private weak var workspace: WorkspaceDocument?

    /// The configuration to run by default.
    @Published var selectedConfigurationID: UUID?
    /// The currently running configuration, if any.
    @Published var runningConfigurationID: UUID?

    private var runningTaskID: UUID?

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    var configurations: [RunConfiguration] {
        workspace?.runConfigurationStore?.configurations ?? []
    }

    var selectedConfiguration: RunConfiguration? {
        configurations.first { $0.id == selectedConfigurationID } ?? configurations.first
    }

    var isRunning: Bool { runningConfigurationID != nil }

    func runSelectedOrFirst() {
        guard let configuration = selectedConfiguration else { return }
        run(configuration)
    }

    func run(_ configuration: RunConfiguration) {
        guard let taskManager = workspace?.taskManager else { return }
        let task = Self.task(from: configuration)
        runningTaskID = task.id
        runningConfigurationID = configuration.id
        Task { await taskManager.runTask(task: task) }
    }

    func stop() {
        guard let taskManager = workspace?.taskManager, let runningTaskID else { return }
        taskManager.terminateTask(taskID: runningTaskID)
        self.runningTaskID = nil
        runningConfigurationID = nil
    }

    private static func task(from configuration: RunConfiguration) -> CETask {
        let task = CETask(
            name: configuration.name,
            target: "",
            workingDirectory: configuration.workingDirectory,
            command: configuration.command,
            environmentVariables: configuration.environment.map {
                CETask.EnvironmentVariable(key: $0.key, value: $0.value)
            }
        )
        task.problemMatcher = configuration.problemMatcher
        return task
    }
}
