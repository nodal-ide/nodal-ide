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
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "SourceControlCoordinator"
    )

    weak var fileManager: CEWorkspaceFileManager? {
        didSet {
            for repo in repositories {
                repo.fileManager = fileManager
            }
        }
    }

    init(workspaceURL: URL, editorManager: EditorManager, shellClient: ShellClient) {
        self.workspaceURL = workspaceURL
        self.editorManager = editorManager
        self.shellClient = shellClient
    }

    func setup() async {
        await rescan()
    }

    func rescan() async {
        let discovered = await scanner.scan(workspaceURL: workspaceURL, shellClient: shellClient)
        reconcile(with: discovered)
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for repo in repositories {
                group.addTask { await repo.refreshAllChangedFiles() }
            }
        }
    }

    /// Returns the most-specific repository manager that owns the given file URL.
    ///
    /// Selects the manager whose root is the longest prefix of the file path,
    /// ensuring a file inside a submodule is attributed to the submodule's repo
    /// rather than the parent.
    func repoForFile(_ url: URL) -> SourceControlManager? {
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        return repositories
            .filter { filePath.hasPrefix($0.workspaceURL.standardizedFileURL.path(percentEncoded: false)) }
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
                Task { await manager.refreshAllChangedFiles() }
            }
        }

        repositories = next
        primaryRepository = next.first(where: {
            $0.workspaceURL.standardizedFileURL == workspaceURL.standardizedFileURL
        }) ?? next.first
    }
}
