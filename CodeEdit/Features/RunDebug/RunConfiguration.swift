//
//  RunConfiguration.swift
//  CodeEdit
//
//  A run/debug/test configuration.
//

import Foundation

struct RunConfiguration: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case run
        case debug
        case test

        var title: String {
            switch self {
            case .run: return "Run"
            case .debug: return "Debug"
            case .test: return "Test"
            }
        }

        var systemImage: String {
            switch self {
            case .run: return "play"
            case .debug: return "ladybug"
            case .test: return "checkmark.diamond"
            }
        }
    }

    struct EnvironmentVariable: Identifiable, Codable, Hashable {
        var id = UUID()
        var key: String = ""
        var value: String = ""

        enum CodingKeys: String, CodingKey {
            case key
            case value
        }
    }

    var id: UUID = UUID()
    var name: String = ""
    var kind: Kind = .run
    /// The command to execute.
    var command: String = ""
    /// Working directory (relative to the workspace, or absolute). Empty = workspace root.
    var workingDirectory: String = ""
    var environment: [EnvironmentVariable] = []
    /// A problem matcher name (e.g. `$gcc`, `$tsc`), or `nil`.
    var problemMatcher: String?
    /// A task (by name) to run before this configuration.
    var preLaunchTask: String?
    /// The debug adapter id (Developer settings ▸ Debug Adapters) — used for `debug` configurations.
    var adapter: String?
    /// The debug request: `launch` (default) or `attach`.
    var debugRequest: String?
    /// The program to launch (debug configurations). Defaults to `command`.
    var program: String?
    /// Space-separated program arguments (debug configurations).
    var arguments: String?

    var isInvalid: Bool { name.isEmpty || command.isEmpty }

    /// The shell command, changing into the working directory first when set.
    var fullCommand: String {
        let cd = workingDirectory.isEmpty ? "" : "cd \(workingDirectory.escapedDirectory()) && "
        return "\(cd)\(command)"
    }

    var environmentDictionary: [String: String] {
        environment.reduce(into: [:]) { $0[$1.key] = $1.value }
    }

    /// Builds a run configuration from an existing task.
    static func from(_ task: CETask) -> RunConfiguration {
        RunConfiguration(
            name: task.name,
            kind: .run,
            command: task.command,
            workingDirectory: task.workingDirectory,
            environment: task.environmentVariables.map { EnvironmentVariable(key: $0.key, value: $0.value) }
        )
    }
}
