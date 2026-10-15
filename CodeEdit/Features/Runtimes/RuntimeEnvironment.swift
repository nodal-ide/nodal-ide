//
//  RuntimeEnvironment.swift
//  CodeEdit
//
//  Computes the environment (PATH prepend) that activates a project's runtimes.
//

import Combine
import Foundation

@MainActor
final class RuntimeEnvironment: ObservableObject {
    static let shared = RuntimeEnvironment()

    /// Cached environment overrides keyed by workspace path.
    private var cache: [String: [String: String]] = [:]

    private init() {}

    /// Resolves the project's runtimes and caches the environment for later synchronous use.
    func refresh(workspace: WorkspaceDocument) async {
        var binPaths: [String] = []
        for kind in [RuntimeKind.node, RuntimeKind.php] {
            if let runtime = await RuntimeResolver.resolve(kind: kind, workspace: workspace) {
                binPaths.append(runtime.executableDirectory.path(percentEncoded: false))
            }
        }

        var environment: [String: String] = [:]
        if !binPaths.isEmpty {
            let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
            environment["PATH"] = binPaths.joined(separator: ":") + ":" + existing
        }

        if let path = workspace.fileURL?.path(percentEncoded: false) {
            cache[path] = environment
        }
    }

    /// The cached environment for a workspace (empty if not resolved yet).
    func cachedEnvironment(for workspaceURL: URL?) -> [String: String] {
        guard let path = workspaceURL?.path(percentEncoded: false) else { return [:] }
        return cache[path] ?? [:]
    }
}
