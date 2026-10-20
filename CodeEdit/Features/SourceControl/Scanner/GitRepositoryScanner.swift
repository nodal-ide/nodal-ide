import Foundation
import OSLog

/// Discovers every git repository root that is reachable from a workspace URL.
///
/// Discovery is performed with a minimal number of shell invocations:
/// - One `git rev-parse --show-toplevel` to locate the workspace's own git root (if any).
/// - One `git submodule foreach --recursive` to enumerate all registered submodule paths.
///
/// No directory walk is performed; complexity is O(1) shell calls regardless of the
/// number of files in the workspace.
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
        let workspacePath = workspaceURL.path(percentEncoded: false)

        let rootURL = await resolveGitRoot(for: workspacePath, shellClient: shellClient)
        let submodulePaths = await resolveSubmodulePaths(
            from: rootURL?.path(percentEncoded: false) ?? workspacePath,
            shellClient: shellClient
        )

        var repos: [DiscoveredRepo] = []

        if let root = rootURL {
            repos.append(DiscoveredRepo(rootURL: root, isSubmodule: false, parentRootURL: nil))
        }

        for subPath in submodulePaths {
            let base = rootURL ?? workspaceURL
            let subURL = base.appending(path: subPath, directoryHint: .isDirectory)
            let standardized = subURL.standardizedFileURL
            guard standardized.path(percentEncoded: false)
                    .hasPrefix(workspacePath) else { continue }
            repos.append(
                DiscoveredRepo(rootURL: standardized, isSubmodule: true, parentRootURL: rootURL)
            )
        }

        return deduplicated(repos)
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
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func deduplicated(_ repos: [DiscoveredRepo]) -> [DiscoveredRepo] {
        var seen = Set<URL>()
        return repos.filter { seen.insert($0.rootURL).inserted }
    }
}
