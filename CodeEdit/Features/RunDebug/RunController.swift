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
        Task { [weak self] in
            guard let self, let workspace = self.workspace else { return }
            await RuntimeEnvironment.shared.refresh(workspace: workspace)
            self.performRun(configuration)
        }
    }

    private func performRun(_ configuration: RunConfiguration) {
        if configuration.kind == .debug {
            startDebug(configuration)
            return
        }
        guard let taskManager = workspace?.taskManager else { return }
        let task = Self.task(from: configuration)
        runningTaskID = task.id
        runningConfigurationID = configuration.id
        Task { await taskManager.runTask(task: task) }
    }

    /// Starts a debug session using the configuration's adapter (Developer settings ▸ Debug Adapters).
    private func startDebug(_ configuration: RunConfiguration) {
        guard let workspace, let debugController = workspace.debugController else { return }
        let adapters = Settings.shared.preferences.developerSettings.debugAdapters
        guard let adapterID = configuration.adapter, adapterID.isEmpty == false,
              let path = adapters[adapterID], !path.isEmpty else {
            return
        }

        let program = (configuration.program?.isEmpty == false ? configuration.program : configuration.command) ?? ""
        let args = (configuration.arguments ?? "").split(separator: " ").map(String.init)
        var launch: [String: JSONValue] = [
            "program": .string(program),
            "args": .array(args.map { .string($0) }),
            "env": .object(configuration.environmentDictionary.mapValues { .string($0) })
        ]
        if !configuration.workingDirectory.isEmpty {
            launch["cwd"] = .string(configuration.workingDirectory)
        }

        let adapterArguments = (Settings.shared.preferences.developerSettings.debugAdapterArguments[adapterID] ?? "")
            .split(separator: " ").map(String.init)

        runningConfigurationID = configuration.id
        debugController.start(
            DebugSession.LaunchOptions(
                adapterExecutable: URL(filePath: path),
                adapterArguments: adapterArguments,
                adapterID: adapterID,
                request: configuration.debugRequest == "attach" ? "attach" : "launch",
                launchArguments: launch,
                workingDirectory: workspace.fileURL,
                environment: RuntimeEnvironment.shared.cachedEnvironment(for: workspace.fileURL)
            )
        )
    }

    func stop() {
        workspace?.debugController?.stop()
        guard let taskManager = workspace?.taskManager, let runningTaskID else {
            runningConfigurationID = nil
            return
        }
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
