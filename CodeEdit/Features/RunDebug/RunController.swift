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
        workspace?.utilityAreaModel?.open(tab: .debugConsole)
        let task = Self.task(from: configuration)
        runningTaskID = task.id
        runningConfigurationID = configuration.id
        Task { await taskManager.runTask(task: task) }
    }

    /// Starts a debug session using the configuration's adapter (Developer settings ▸ Debug Adapters),
    /// falling back to the project runtime's debugger when no adapter is configured.
    private func startDebug(_ configuration: RunConfiguration) {
        guard let workspace, let debugController = workspace.debugController else { return }
        let program = (configuration.program?.isEmpty == false ? configuration.program : configuration.command) ?? ""
        let args = (configuration.arguments ?? "").split(separator: " ").map(String.init)

        // Web-server flow: start the listener, then launch the dev server with Xdebug enabled.
        if let serverCommand = configuration.serverCommand,
           !serverCommand.trimmingCharacters(in: .whitespaces).isEmpty {
            startWebServerDebug(configuration, serverCommand: serverCommand)
            return
        }

        let adapters = Settings.shared.preferences.developerSettings.debugAdapters
        if let adapterID = configuration.adapter, adapterID.isEmpty == false,
           let path = adapters[adapterID], !path.isEmpty {
            startExplicitAdapterDebug(
                configuration,
                adapterID: adapterID,
                path: path,
                program: program,
                args: args
            )
            return
        }

        // No explicit adapter: auto-wire from the project's runtime.
        runningConfigurationID = configuration.id
        Task { [weak self] in
            await self?.startAutoDebug(
                program: program,
                arguments: args,
                clientPort: configuration.clientPort,
                pathMappings: configuration.pathMappingDictionary
            )
        }
    }

    /// Starts a debug session using an explicitly configured adapter.
    private func startExplicitAdapterDebug(
        _ configuration: RunConfiguration,
        adapterID: String,
        path: String,
        program: String,
        args: [String]
    ) {
        guard let workspace, let debugController = workspace.debugController else { return }
        // With no program this is a "listen" session (the adapter waits for Xdebug to connect);
        // `vscode-php-debug` has no `attach` request, so it's always a `launch`.
        var launch: [String: JSONValue] = [:]
        if !program.isEmpty {
            launch["program"] = .string(program)
            launch["args"] = .array(args.map { .string($0) })
            if !configuration.environmentDictionary.isEmpty {
                launch["env"] = .object(configuration.environmentDictionary.mapValues { .string($0) })
            }
            if !configuration.workingDirectory.isEmpty {
                launch["cwd"] = .string(configuration.workingDirectory)
            }
        }
        DebuggerAutoWiring.apply(
            launch: &launch,
            clientPort: configuration.clientPort
                ?? Settings.shared.preferences.developerSettings.phpDebugClientPort,
            pathMappings: configuration.pathMappingDictionary
        )

        let adapterArguments = (
            Settings.shared.preferences.developerSettings.debugAdapterArguments[adapterID] ?? ""
        ).split(separator: " ").map(String.init)

        workspace.utilityAreaModel?.open(tab: .debug)
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

    /// Starts a listener and launches the configuration's dev server with Xdebug enabled.
    ///
    /// This is the "run my web server and debug the requests" flow: the adapter waits on the client
    /// port while the server command runs (in the task runner) with `XDEBUG_MODE=debug`, so web
    /// requests stopped at breakpoints appear in the Debug tab.
    private func startWebServerDebug(_ configuration: RunConfiguration, serverCommand: String) {
        guard let workspace, let debugController = workspace.debugController else { return }
        let port = configuration.clientPort
            ?? Settings.shared.preferences.developerSettings.phpDebugClientPort

        Task { [weak self] in
            guard let self, let workspace = self.workspace else { return }
            await RuntimeEnvironment.shared.refresh(workspace: workspace)
            guard let options = await DebuggerAutoWiring.listenOptions(workspace: workspace, port: port) else {
                DebuggerAutoWiring.reportUnavailable(kind: .php)
                return
            }
            runningConfigurationID = configuration.id
            debugController.start(options)

            var environment = configuration.environmentDictionary
            environment["XDEBUG_MODE"] = "debug"
            environment["XDEBUG_CONFIG"] = "client_port=\(port) start_with_request=yes"
            let task = CETask(
                name: configuration.name,
                target: "",
                workingDirectory: configuration.workingDirectory,
                command: serverCommand,
                environmentVariables: environment.map { CETask.EnvironmentVariable(key: $0.key, value: $0.value) }
            )
            runningTaskID = task.id
            workspace.utilityAreaModel?.open(tab: .debug)
            Task { await workspace.taskManager?.runTask(task: task) }
        }
    }

    /// Starts a debug session for the active file, auto-wired from the project's runtime.
    func debugCurrentFile() {
        guard let workspace,
              let url = workspace.editorManager?.activeEditor.selectedTab?.file.url else { return }
        Task { [weak self] in
            await self?.startAutoDebug(program: url.path(percentEncoded: false))
        }
    }

    /// Listens for an incoming Xdebug connection (attach) using the project's PHP runtime.
    func listenForXdebug() {
        guard let workspace, workspace.debugController != nil else { return }
        Task { [weak self] in
            guard let self, let workspace = self.workspace else { return }
            await RuntimeEnvironment.shared.refresh(workspace: workspace)
            guard let options = await DebuggerAutoWiring.listenOptions(workspace: workspace) else {
                DebuggerAutoWiring.reportUnavailable(kind: .php)
                return
            }
            workspace.utilityAreaModel?.open(tab: .debug)
            workspace.debugController?.start(options)
        }
    }

    /// Starts a debug session using the runtime's debugger configuration.
    private func startAutoDebug(
        program: String,
        arguments: [String] = [],
        clientPort: Int? = nil,
        pathMappings: [String: String] = [:]
    ) async {
        guard let workspace, let debugController = workspace.debugController else { return }
        await RuntimeEnvironment.shared.refresh(workspace: workspace)
        guard let options = await DebuggerAutoWiring.options(
            workspace: workspace,
            program: program,
            arguments: arguments,
            clientPort: clientPort,
            pathMappings: pathMappings
        ) else {
            DebuggerAutoWiring.reportUnavailable(kind: DebuggerAutoWiring.kind(forProgram: program))
            return
        }
        workspace.utilityAreaModel?.open(tab: .debug)
        debugController.start(options)
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
