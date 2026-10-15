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

    /// Running/finished install & uninstall jobs (surfaced in the activity area).
    let jobs = RuntimeJobCenter()

    /// Detected host tooling (Homebrew, developer tools, network).
    let tooling = RuntimeTooling()

    private(set) var providers: [RuntimeKind: any RuntimeProvider] = [:]

    private init() {
        register(NodeRuntimeProvider())
        register(PHPRuntimeProvider())
    }

    // MARK: - Install / uninstall

    func install(kind: RuntimeKind, version: RuntimeVersion) async {
        guard let provider = provider(for: kind) else { return }
        await jobs.run(kind: kind, version: version.version, operation: .install) { progress in
            try await provider.install(version, progress: progress)
        }
    }

    func uninstall(_ runtime: InstalledRuntime) async {
        guard let provider = provider(for: runtime.kind) else { return }
        await jobs.run(kind: runtime.kind, version: runtime.version, operation: .uninstall) { progress in
            let _ = progress
            try await provider.uninstall(runtime)
        }
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
