import Foundation
import OSLog

/// Discovers every git repository root that is reachable from a workspace URL.
///
/// Discovery is performed with a minimal number of shell invocations:
/// - One `git rev-parse --show-toplevel` to locate the workspace's own git root (if any).
/// - One `git submodule foreach --recursive` to enumerate registered submodule paths.
/// - When the workspace is not itself inside a git repository, one pruned `find`
///   locates independently versioned repositories (the multi-root layout).
///
/// The multi-root walk only runs for non-git workspaces. It prunes common build and
/// dependency directories so discovery scales with the number of repository roots
/// rather than the number of files in a typical project.
actor GitRepositoryScanner {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "GitRepositoryScanner"
    )

    struct DiscoveredRepo: Sendable, Hashable {
        let rootURL: URL
        let isSubmodule: Bool
        let parentRootURL: URL?
    }

    func scan(workspaceURL: URL, shellClient: ShellClient) async -> [DiscoveredRepo] {
        let workspaceURL = workspaceURL.standardizedFileURL
        let workspacePath = workspaceURL.path(percentEncoded: false)

        let rootURL = await resolveGitRoot(for: workspacePath, shellClient: shellClient)

        if let rootURL {
            let submodulePaths = await resolveSubmodulePaths(
                from: rootURL.path(percentEncoded: false),
                shellClient: shellClient
            )
            let submoduleRoots = uniqueSubmoduleRoots(
                from: submodulePaths,
                baseURL: rootURL,
                workspaceURL: workspaceURL
            )

            var repositories = [
                DiscoveredRepo(rootURL: rootURL, isSubmodule: false, parentRootURL: nil)
            ]

            for submoduleRoot in submoduleRoots {
                repositories.append(
                    DiscoveredRepo(
                        rootURL: submoduleRoot,
                        isSubmodule: true,
                        parentRootURL: mostSpecificParent(
                            for: submoduleRoot,
                            rootURL: rootURL,
                            submoduleRoots: submoduleRoots
                        )
                    )
                )
            }

            return repositories
        }

        let independentRoots = await resolveIndependentRepositoryRoots(
            in: workspaceURL,
            shellClient: shellClient
        )
        return independentRoots.map { rootURL in
            DiscoveredRepo(
                rootURL: rootURL,
                isSubmodule: false,
                parentRootURL: mostSpecificParent(
                    for: rootURL,
                    rootURL: nil,
                    submoduleRoots: independentRoots
                )
            )
        }
    }

    /// Finds independently versioned git roots inside a workspace that is not itself
    /// a git repository. This is the multi-root layout used by monorepo parents that
    /// contain separate packages.
    private func resolveIndependentRepositoryRoots(
        in workspaceURL: URL,
        shellClient: ShellClient
    ) async -> [URL] {
        let command = """
        cd \(workspaceURL.path(percentEncoded: false).escapedDirectory()); \
        find . \\( \
            -name node_modules -o -name .build -o -name DerivedData -o -name .venv -o \
            -name Pods -o -name .cache -o -name build -o -name dist -o -name target -o -name .next \
        \\) -prune -o -name .git -prune -print
        """
        guard let output = try? shellClient.run(command) else { return [] }

        var seen = Set<URL>()
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { path in
                let relativePath = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
                return workspaceURL
                    .appending(path: relativePath, directoryHint: .notDirectory)
                    .deletingLastPathComponent()
                    .standardizedFileURL
            }
            .filter { workspaceURL.componentCompare($0) || workspaceURL.containsSubPath($0) }
            .filter { seen.insert($0).inserted }
            .sorted {
                let depthDifference = $0.pathComponents.count - $1.pathComponents.count
                if depthDifference != 0 {
                    return depthDifference < 0
                }
                return $0.path(percentEncoded: false)
                    .localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending
            }
    }

    private func resolveGitRoot(for path: String, shellClient: ShellClient) async -> URL? {
        let command = "cd \(path.escapedDirectory()); git rev-parse --show-toplevel"
        guard let output = try? shellClient.run(command),
              !output.contains("fatal:") else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(filePath: trimmed, directoryHint: .isDirectory).standardizedFileURL
    }

    private func resolveSubmodulePaths(from path: String, shellClient: ShellClient) async -> [String] {
        let command = "cd \(path.escapedDirectory()); git submodule foreach --recursive --quiet 'echo $displaypath'"
        guard let output = try? shellClient.run(command),
              !output.contains("fatal:") else { return [] }
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Resolves submodule paths to unique repository roots inside the workspace.
    ///
    /// Submodule paths are displayed relative to the traversal root, which may be a parent
    /// repository when the workspace itself is nested. Paths outside the workspace are ignored.
    private func uniqueSubmoduleRoots(
        from paths: [String],
        baseURL: URL,
        workspaceURL: URL
    ) -> [URL] {
        var seen = Set<URL>()
        return paths
            .map { baseURL.appending(path: $0, directoryHint: .isDirectory).standardizedFileURL }
            .filter { workspaceURL.componentCompare($0) || workspaceURL.containsSubPath($0) }
            .filter { seen.insert($0).inserted }
            .sorted {
                let depthDifference = $0.pathComponents.count - $1.pathComponents.count
                if depthDifference != 0 {
                    return depthDifference < 0
                }
                return $0.path(percentEncoded: false)
                    .localizedStandardCompare($1.path(percentEncoded: false)) == .orderedAscending
            }
    }

    /// Returns the closest discovered submodule root containing `submoduleRoot`, falling
    /// back to the workspace's git root.
    private func mostSpecificParent(
        for submoduleRoot: URL,
        rootURL: URL?,
        submoduleRoots: [URL]
    ) -> URL? {
        let parent = submoduleRoots
            .filter { $0 != submoduleRoot && $0.containsSubPath(submoduleRoot) }
            .max { $0.pathComponents.count < $1.pathComponents.count }
        return parent ?? rootURL
    }
}
