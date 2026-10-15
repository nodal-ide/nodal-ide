//
//  DebugSession.swift
//  CodeEdit
//
//  Manages a debug adapter session: launch, lifecycle, threads, stack, scopes, variables, console.
//

import Combine
import Foundation

@MainActor
final class DebugSession: ObservableObject {
    enum State: Equatable {
        case inactive
        case launching
        case running
        case stopped(reason: String)
        case terminated

        var isStopped: Bool {
            if case .stopped = self { return true }
            return false
        }

        var isActive: Bool {
            switch self {
            case .launching, .running, .stopped: return true
            case .inactive, .terminated: return false
            }
        }
    }

    struct LaunchOptions {
        let adapterExecutable: URL
        var adapterArguments: [String] = []
        let adapterID: String
        let launchArguments: [String: JSONValue]
        var workingDirectory: URL?
        var environment: [String: String]?
    }

    @Published private(set) var state: State = .inactive
    @Published private(set) var threads: [DAPThread] = []
    @Published var currentThreadID: Int?
    @Published private(set) var callStack: [DAPStackFrame] = []
    @Published var currentFrameID: Int?
    @Published private(set) var scopes: [DAPScope] = []
    @Published private(set) var variablesByReference: [Int: [DAPVariable]] = [:]
    @Published private(set) var console: [String] = []

    private var client: DebugAdapterClient?
    private var configurationDone = false
    private var launchTask: Task<Void, Never>?

    // MARK: - Launch / stop

    func start(_ options: LaunchOptions) {
        stop()
        state = .launching
        threads = []
        callStack = []
        scopes = []
        variablesByReference = [:]
        console = []
        currentThreadID = nil
        currentFrameID = nil
        configurationDone = false

        let client = DebugAdapterClient(
            executable: options.adapterExecutable,
            arguments: options.adapterArguments,
            environment: options.environment,
            workingDirectory: options.workingDirectory
        )
        client.onLog = { [weak self] text in self?.console.append(text) }
        client.onEvent = { [weak self] event in self?.handle(event) }
        client.onTerminated = { [weak self] _ in self?.handleTerminated() }
        self.client = client

        do {
            try client.start()
        } catch {
            console.append("Failed to start debug adapter: \(error.localizedDescription)")
            state = .terminated
            self.client = nil
            return
        }

        Task { await performHandshake(options) }
    }

    func stop() {
        launchTask?.cancel()
        launchTask = nil
        client?.stop()
        client = nil
        if state != .terminated {
            state = .inactive
        }
    }

    private func performHandshake(_ options: LaunchOptions) async {
        guard let client else { return }
        do {
            let arguments = try JSONValue.encode(DAPInitializeArguments(adapterID: options.adapterID))
            _ = try await client.send(command: "initialize", arguments: arguments)
        } catch {
            console.append("initialize failed: \(error.localizedDescription)")
            return
        }

        // Launch — the adapter may not respond until `configurationDone` is received.
        launchTask = Task { [weak self] in
            guard let self, let client = self.client else { return }
            _ = try? await client.send(command: "launch", arguments: .object(options.launchArguments))
            if self.state == .launching {
                self.state = .running
            }
            await self.refreshThreads()
        }

        // Fallback: configure even if the adapter never sends `initialized`.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.sendConfigurationDoneIfNeeded()
        }
    }

    private func sendConfigurationDoneIfNeeded() {
        guard !configurationDone, let client else { return }
        configurationDone = true
        Task { _ = try? await client.send(command: "configurationDone") }
    }

    // MARK: - Execution control

    func continueExecution() {
        guard let threadID = currentThreadID else { return }
        callStack = []
        scopes = []
        send("continue", ["threadId": threadID])
    }

    func pause() {
        guard let threadID = currentThreadID else { return }
        send("pause", ["threadId": threadID])
    }

    func stepOver() { step("next") }
    func stepInto() { step("stepIn") }
    func stepOut() { step("stepOut") }

    private func step(_ command: String) {
        guard let threadID = currentThreadID else { return }
        send(command, ["threadId": threadID])
    }

    private func send(_ command: String, _ arguments: [String: Int]) {
        guard let client else { return }
        let value = JSONValue.object(arguments.mapValues { .number(Double($0)) })
        Task { _ = try? await client.send(command: command, arguments: value) }
    }

    // MARK: - Introspection

    func selectFrame(_ frame: DAPStackFrame) async {
        currentFrameID = frame.id
        await refreshScopes(frameID: frame.id)
    }

    func loadVariables(reference: Int) async {
        guard let client, let response = try? await client.send(
            command: "variables",
            arguments: try? JSONValue.encode(DAPVariablesArguments(variablesReference: reference))
        ), let body = response.body, let result = try? body.decode(DAPVariablesResponse.self) else {
            return
        }
        variablesByReference[reference] = result.variables
    }

    func evaluate(_ expression: String, frameID: Int? = nil) async -> String? {
        guard let client else { return nil }
        let arguments = try? JSONValue.encode(DAPEvaluateArguments(expression: expression, frameId: frameID))
        guard let response = try? await client.send(command: "evaluate", arguments: arguments),
              let body = response.body, let result = try? body.decode(DAPEvaluateResponse.self) else {
            return nil
        }
        return result.result
    }

    private func refreshThreads() async {
        guard let client, let response = try? await client.send(command: "threads"),
              let body = response.body, let result = try? body.decode(DAPThreadsResponse.self) else {
            return
        }
        threads = result.threads
        if currentThreadID == nil {
            currentThreadID = result.threads.first?.id
        }
    }

    private func refreshStackTrace(threadID: Int) async {
        guard let client, let response = try? await client.send(
            command: "stackTrace",
            arguments: try? JSONValue.encode(DAPStackTraceArguments(threadId: threadID))
        ), let body = response.body, let result = try? body.decode(DAPStackTraceResponse.self) else {
            return
        }
        callStack = result.stackFrames
        if let first = result.stackFrames.first {
            currentFrameID = first.id
            await refreshScopes(frameID: first.id)
        }
    }

    private func refreshScopes(frameID: Int) async {
        guard let client, let response = try? await client.send(
            command: "scopes",
            arguments: try? JSONValue.encode(DAPScopesArguments(frameId: frameID))
        ), let body = response.body, let result = try? body.decode(DAPScopesResponse.self) else {
            return
        }
        scopes = result.scopes
    }

    // MARK: - Events

    private func handle(_ event: DAPEvent) {
        switch event.event {
        case "initialized":
            sendConfigurationDoneIfNeeded()
        case "stopped":
            guard let body = event.body, let stopped = try? body.decode(DAPStoppedEventBody.self) else { return }
            state = .stopped(reason: stopped.reason)
            if let threadID = stopped.threadId {
                currentThreadID = threadID
            }
            Task { [weak self] in
                guard let self else { return }
                await self.refreshThreads()
                if let threadID = self.currentThreadID {
                    await self.refreshStackTrace(threadID: threadID)
                }
            }
        case "continued":
            state = .running
            callStack = []
            scopes = []
            if let body = event.body, let continued = try? body.decode(DAPContinuedEventBody.self),
               let threadID = continued.threadId {
                currentThreadID = threadID
            }
        case "output":
            if let body = event.body, let output = try? body.decode(DAPOutputEventBody.self) {
                console.append(output.output)
            }
        case "terminated", "exited":
            state = .terminated
        default:
            break
        }
    }

    private func handleTerminated() {
        client = nil
        state = .terminated
    }
}
