//
//  DebuggerAutoWiring.swift
//  CodeEdit
//
//  Auto-wires a debug session from the project's runtime (interpreter + adapter).
//

import Foundation
import SwiftUI

@MainActor
enum DebuggerAutoWiring {
    /// Infers the runtime kind for a program from its file extension.
    static func kind(forProgram program: String) -> RuntimeKind {
        let ext = URL(filePath: program).pathExtension.lowercased()
        if ["js", "mjs", "cjs", "ts", "tsx", "jsx"].contains(ext) {
            return .node
        }
        return .php
    }

    /// Builds launch options for a program using the project's resolved runtime + adapter.
    static func options(
        workspace: WorkspaceDocument,
        program: String,
        arguments: [String] = [],
        request: String = "launch",
        clientPort: Int? = nil,
        pathMappings: [String: String] = [:]
    ) async -> DebugSession.LaunchOptions? {
        guard !program.isEmpty else { return nil }
        let runtimeKind = kind(forProgram: program)
        guard let provider = RuntimeManager.shared.provider(for: runtimeKind),
              let runtime = await RuntimeResolver.resolve(kind: runtimeKind, workspace: workspace),
              let debugger = provider.debugger(for: runtime),
              let adapter = adapterExecutable(for: debugger) else {
            return nil
        }

        var launch = debugger.launchArguments(
            program: program,
            arguments: arguments,
            cwd: workspace.fileURL?.path(percentEncoded: false)
        )
        Self.apply(launch: &launch, clientPort: clientPort, pathMappings: pathMappings)
        return makeOptions(
            workspace: workspace,
            debugger: debugger,
            adapter: adapter,
            request: request,
            launchArguments: launch
        )
    }

    /// Merges the PHP/Xdebug `port` and `pathMappings` overrides into a launch-arguments dictionary.
    static func apply(launch: inout [String: JSONValue], clientPort: Int?, pathMappings: [String: String]) {
        if let clientPort {
            launch["port"] = .number(Double(clientPort))
        }
        if !pathMappings.isEmpty {
            launch["pathMappings"] = .object(pathMappings.mapValues { .string($0) })
        }
    }

    /// Builds a **listening** (attach) session for the project's PHP/Xdebug runtime. The adapter waits
    /// for Xdebug to connect (start a request with `XDEBUG_MODE=debug`), so no program is launched.
    static func listenOptions(
        workspace: WorkspaceDocument,
        host: String = "127.0.0.1",
        port: Int? = nil
    ) async -> DebugSession.LaunchOptions? {
        guard let provider = RuntimeManager.shared.provider(for: .php),
              let runtime = await RuntimeResolver.resolve(kind: .php, workspace: workspace),
              let debugger = provider.debugger(for: runtime),
              let adapter = adapterExecutable(for: debugger) else {
            return nil
        }
        let port = port ?? Settings.shared.preferences.developerSettings.phpDebugClientPort
        return makeOptions(
            workspace: workspace,
            debugger: debugger,
            adapter: adapter,
            request: "attach",
            launchArguments: debugger.attachArguments(host: host, port: port)
        )
    }

    /// Assembles launch options with the project's runtime environment (PATH) merged in.
    private static func makeOptions(
        workspace: WorkspaceDocument,
        debugger: RuntimeDebugger,
        adapter: URL,
        request: String,
        launchArguments: [String: JSONValue]
    ) -> DebugSession.LaunchOptions {
        var environment = debugger.environment
        environment.merge(RuntimeEnvironment.shared.cachedEnvironment(for: workspace.fileURL)) { _, new in new }
        let adapterArguments = (
            Settings.shared.preferences.developerSettings.debugAdapterArguments[debugger.adapterID] ?? ""
        ).split(separator: " ").map(String.init)

        return DebugSession.LaunchOptions(
            adapterExecutable: adapter,
            adapterArguments: adapterArguments,
            adapterID: debugger.adapterID,
            request: request,
            launchArguments: launchArguments,
            workingDirectory: workspace.fileURL,
            environment: environment
        )
    }

    /// The configured adapter for a debugger, else the first known candidate on `PATH`.
    static func adapterExecutable(for debugger: RuntimeDebugger) -> URL? {
        let adapters = Settings.shared.preferences.developerSettings.debugAdapters
        if let configured = adapters[debugger.adapterID], !configured.isEmpty,
           FileManager.default.isExecutableFile(atPath: configured) {
            return URL(filePath: configured)
        }
        for candidate in debugger.adapterCandidates {
            if let path = RuntimeShell.whichAll(candidate).first {
                return URL(filePath: path)
            }
        }
        return nil
    }

    /// Posts a notification explaining that no debug adapter is available, with a fix action.
    static func reportUnavailable(kind: RuntimeKind) {
        _ = NotificationManager.shared.post(
            iconSymbol: "ladybug",
            title: "No \(kind.title) debug adapter found",
            description: "Set one in Settings ▸ Developer ▸ Debug Adapters.",
            actionButtonTitle: "Open Settings",
            action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            isSticky: true
        )
    }
}
