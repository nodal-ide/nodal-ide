//
//  RuntimeManager.swift
//  CodeEdit
//
//  Registers runtime providers and resolves versions for projects.
//

import Foundation

/// Holds the registered ``RuntimeProvider``s and app-level runtime state.
@MainActor
final class RuntimeManager: ObservableObject {
    static let shared = RuntimeManager()

    /// The managed install root: `~/.codeedit/runtimes`.
    static var runtimesRoot: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codeedit")
            .appending(path: "runtimes")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private(set) var providers: [RuntimeKind: any RuntimeProvider] = [:]

    private init() {
        register(NodeRuntimeProvider())
        register(PHPRuntimeProvider())
    }

    func register(_ provider: any RuntimeProvider) {
        providers[provider.kind] = provider
    }

    func provider(for kind: RuntimeKind) -> (any RuntimeProvider)? {
        providers[kind]
    }

    var allProviders: [any RuntimeProvider] {
        RuntimeKind.allCases.compactMap { providers[$0] }
    }
}
