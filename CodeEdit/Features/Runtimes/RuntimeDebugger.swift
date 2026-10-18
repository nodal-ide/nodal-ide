//
//  RuntimeDebugger.swift
//  CodeEdit
//
//  Describes how to debug a program with a given runtime (adapter + launch template).
//

import Foundation

/// The debugger wiring for a runtime: which adapter to use and how to build a launch request.
struct RuntimeDebugger {
    /// The runtime kind this debugger belongs to.
    let kind: RuntimeKind
    /// The adapter id used for the Developer settings `debugAdapters` lookup.
    let adapterID: String
    /// Known adapter executables to look up on `PATH` (first match wins).
    let adapterCandidates: [String]
    /// Extra environment for the adapter/process (e.g. `XDEBUG_MODE=debug`).
    let environment: [String: String]
    /// The interpreter to run the program with, if applicable.
    let interpreterPath: String?

    /// Builds the DAP `launch`/`attach` arguments for a program.
    func launchArguments(program: String, arguments: [String], cwd: String?) -> [String: JSONValue] {
        var launch: [String: JSONValue] = [
            "program": .string(program),
            "args": .array(arguments.map { .string($0) })
        ]
        if let cwd {
            launch["cwd"] = .string(cwd)
        }
        switch kind {
        case .node:
            launch["type"] = .string("node")
        case .php:
            if let interpreterPath {
                launch["runtimeExecutable"] = .string(interpreterPath)
            }
            // Ensure the launched script starts a debug session (XDEBUG_CONFIG can't set this).
            launch["runtimeArgs"] = .array([.string("-dxdebug.start_with_request=yes")])
            launch["port"] = .number(Double(AppServices.settings.preferences.developerSettings.phpDebugClientPort))
            launch["xdebugSettings"] = .object([
                "max_children": .number(128),
                "max_data": .number(2048),
                "max_depth": .number(5)
            ])
        case .typescript:
            break
        }
        return launch
    }

    /// Builds the DAP `launch` arguments for a **listen** session (no `program`): the adapter waits
    /// for the runtime (Xdebug) to connect on `port`.
    func listenArguments(port: Int) -> [String: JSONValue] {
        var args: [String: JSONValue] = ["port": .number(Double(port))]
        switch kind {
        case .php:
            args["xdebugSettings"] = .object([
                "max_children": .number(128),
                "max_data": .number(2048),
                "max_depth": .number(5)
            ])
            // Allow several concurrent Xdebug connections (a dev-server wrapper plus each request).
            args["maxConnections"] = .number(10)
        case .node, .typescript:
            break
        }
        return args
    }
}
