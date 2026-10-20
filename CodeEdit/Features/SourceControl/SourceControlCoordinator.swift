import Foundation
import Combine
import OSLog

/// Owns and coordinates every `SourceControlManager` instance active in a workspace.
///
/// When a workspace contains git submodules (or when the workspace root is itself not
/// a git repo but lives inside one), the coordinator creates one `SourceControlManager`
/// per discovered root and keeps them in sync.
///
/// For single-repo workspaces the coordinator is transparent: callers that access
/// `primaryRepository` receive exactly the same manager they always did.
@MainActor
final class SourceControlCoordinator: ObservableObject {
    @Published private(set) var repositories: [SourceControlManager] = []
    @Published private(set) var primaryRepository: SourceControlManager?

    private let workspaceURL: URL
    private let editorManager: EditorManager
    private let shellClient: ShellClient
    private let scanner = GitRepositoryScanner()
    private let fallbackRepository: SourceControlManager
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "SourceControlCoordinator"
    )

    private var isRefreshingAll = false
    private var refreshAllAgain = false
    private var isRefreshingMetadata = false
    private var refreshMetadataAgain = false
    private var nextSecondaryFetchIndex = 0

    weak var fileManager: CEWorkspaceFileManager? {
        didSet {
            fallbackRepository.fileManager = fileManager
            for repo in repositories {
                repo.fileManager = fileManager
            }
        }
    }

    init(workspaceURL: URL, editorManager: EditorManager, shellClient: ShellClient) {
        self.workspaceURL = workspaceURL
        self.editorManager = editorManager
        self.shellClient = shellClient
        let fallbackRepository = SourceControlManager(
            workspaceURL: workspaceURL,
            editorManager: editorManager
        )
        self.fallbackRepository = fallbackRepository
        self.primaryRepository = fallbackRepository
    }

    func setup() async {
        await rescan()
    }

    func rescan() async {
        let discovered = await scanner.scan(workspaceURL: workspaceURL, shellClient: shellClient)
        reconcile(with: discovered)
    }

    /// Refreshes the working-tree status for every repository.
    ///
    /// File-system events can arrive in bursts while a workspace is opening. Coalescing
    /// overlapping requests prevents a queue of full status scans for every repository.
    func refreshAll() async {
        guard !isRefreshingAll else {
            refreshAllAgain = true
            return
        }
        isRefreshingAll = true
        repeat {
            refreshAllAgain = false
            await withTaskGroup(of: Void.self) { group in
                for repo in repositories {
                    group.addTask { await repo.refreshAllChangedFiles() }
                }
            }
        } while refreshAllAgain
        isRefreshingAll = false
    }

    /// Refreshes branch, remote, and stash metadata for every repository concurrently.
    ///
    /// Coalesces overlapping requests so switching to the source control navigator while
    /// repository discovery is still settling doesn't trigger duplicate metadata passes.
    func refreshAllMetadata() async {
        guard !isRefreshingMetadata else {
            refreshMetadataAgain = true
            return
        }
        isRefreshingMetadata = true
        repeat {
            refreshMetadataAgain = false
            await withTaskGroup(of: Void.self) { group in
                for repo in repositories {
                    group.addTask {
                        await repo.refreshCurrentBranch()
                        await repo.refreshBranches()
                        do {
                            try await repo.refreshRemotes()
                            try await repo.refreshStashEntries()
                        } catch {
                            repo.logger.error("Failed to refresh repository metadata: \(error)")
                        }
                    }
                }
            }
        } while refreshMetadataAgain
        isRefreshingMetadata = false
    }

    /// Re-validates every repository concurrently.
    func validateAll() async {
        await withTaskGroup(of: Void.self) { group in
            for repo in repositories {
                group.addTask { try? await repo.validate() }
            }
        }
    }

    /// Fetches every repository concurrently.
    func fetchAll() async {
        await withTaskGroup(of: Void.self) { group in
            for repo in repositories {
                group.addTask {
                    do {
                        try await repo.fetch()
                    } catch {
                        repo.logger.error("Failed to fetch repository: \(error)")
                    }
                }
            }
        }
    }

    /// Fetches the active repository plus one other repository in round-robin order.
    ///
    /// Fetching every repository in a multi-repo workspace at once starts many network
    /// operations simultaneously. Spreading secondary repositories across ticks keeps
    /// server status reasonably fresh without making the navigator unresponsive.
    func fetchScheduledRepositories() async {
        guard let primaryRepository, primaryRepository.isGitRepository else {
            return
        }
        do {
            try await primaryRepository.fetch()
        } catch {
            primaryRepository.logger.error("Failed to fetch primary repository: \(error)")
        }

        let secondaryRepositories = repositories.filter {
            $0 !== primaryRepository && $0.isGitRepository
        }
        guard !secondaryRepositories.isEmpty else {
            return
        }
        let repository = secondaryRepositories[nextSecondaryFetchIndex % secondaryRepositories.count]
        nextSecondaryFetchIndex = (nextSecondaryFetchIndex + 1) % secondaryRepositories.count
        do {
            try await repository.fetch()
        } catch {
            repository.logger.error("Failed to fetch repository: \(error)")
        }
    }

    /// Returns the most-specific repository manager that owns the given file URL.
    ///
    /// Selects the manager whose root is the longest path prefix of the file path,
    /// ensuring a file inside a submodule is attributed to the submodule's repo
    /// rather than the parent.
    func repoForFile(_ url: URL) -> SourceControlManager? {
        Self.mostSpecificRepository(for: url, in: repositories)
    }

    /// Resolves the deepest repository containing `url`.
    ///
    /// Paths are compared by components so `/workspace-other` is never treated as
    /// a child of `/workspace`.
    static func mostSpecificRepository(
        for url: URL,
        in repositories: [SourceControlManager]
    ) -> SourceControlManager? {
        let url = url.standardizedFileURL
        return repositories
            .filter {
                let root = $0.workspaceURL.standardizedFileURL
                return root.componentCompare(url) || root.containsSubPath(url)
            }
            .max { $0.workspaceURL.pathComponents.count < $1.workspaceURL.pathComponents.count }
    }

    private func reconcile(with discovered: [GitRepositoryScanner.DiscoveredRepo]) {
        let existingByURL = Dictionary(
            uniqueKeysWithValues: repositories.map { ($0.workspaceURL.standardizedFileURL, $0) }
        )
        var next: [SourceControlManager] = []

        for repo in discovered {
            let key = repo.rootURL.standardizedFileURL
            if let existing = existingByURL[key] {
                existing.isSubmodule = repo.isSubmodule
                existing.parentRepoURL = repo.parentRootURL
                next.append(existing)
            } else {
                let manager = SourceControlManager(
                    workspaceURL: repo.rootURL,
                    editorManager: editorManager,
                    isSubmodule: repo.isSubmodule,
                    parentRepoURL: repo.parentRootURL
                )
                manager.fileManager = fileManager
                next.append(manager)
                Task {
                    try? await manager.validate()
                    await manager.refreshAllChangedFiles()
                    await manager.refreshChangesMetadata()
                }
            }
        }

        repositories = next
        primaryRepository = next.first(where: {
            $0.workspaceURL.standardizedFileURL == workspaceURL.standardizedFileURL
        }) ?? next.first ?? fallbackRepository
    }
}
