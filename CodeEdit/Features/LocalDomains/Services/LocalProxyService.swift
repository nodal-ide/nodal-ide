import Foundation

/// App-scoped service that owns everything shared across windows: the single-instance lock and the
/// domain registry (nginx, certificates, and the privileged relay join it in later tasks).
@MainActor
final class LocalProxyService {
    static let shared = LocalProxyService()

    let lock: LocalProxyLock
    let registry = SiteRegistry()
    let tooling: LocalServerTooling
    let nginx: NginxController
    let authority: CertificateAuthority

    private let pipeline: LocalSitePipeline
    private var isPrepared = false

    init(lock: LocalProxyLock = LocalProxyLock(), tooling: LocalServerTooling? = nil) {
        let tooling = tooling ?? LocalServerTooling()
        self.lock = lock
        self.tooling = tooling
        self.nginx = NginxController()
        self.authority = CertificateAuthority(tooling: tooling)
        self.pipeline = LocalSitePipeline(
            tooling: tooling,
            authority: authority,
            nginx: nginx,
            registry: registry,
            portMode: { AppServices.settings.preferences.localDomains.portMode }
        )
    }

    /// Takes the cross-process lock once, before any site work begins. Idempotent.
    func prepare() throws {
        guard !isPrepared else {
            return
        }
        try lock.acquire()
        isPrepared = true
    }

    /// Builds the per-project operations pipeline for a workspace. `site` supplies the live project
    /// settings at start/reload time, so edits are picked up without recreating the coordinator.
    func makeOperations(
        workspaceURL: URL,
        site: @escaping @MainActor () -> LocalSiteSettings,
        taskManager: TaskManager? = nil
    ) -> any LocalSiteOperations {
        SitePipelineOperations(
            workspaceURL: workspaceURL,
            pipeline: pipeline,
            loadSite: site,
            prepare: { [weak self] in try self?.prepare() },
            upstream: taskManager.map(TaskManagerProxyUpstream.init(taskManager:))
        )
    }

    /// Releases the app-scoped proxy resources. Called from the deferred app-termination path.
    func terminate() async {
        await pipeline.shutdown()
        registry.removeAll()
        lock.release()
        isPrepared = false
    }
}

/// Temporary no-op ``LocalSiteOperations`` kept for tests and previews.
@MainActor
final class NoopLocalSiteOperations: LocalSiteOperations {
    let workspaceURL: URL

    init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    func start(rollback: SiteRollback) async throws { }

    func stop() async { }

    func reload() async throws { }
}
