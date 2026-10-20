import Foundation

/// The fixed loopback ports used for local sites (until the portless relay lands).
enum LocalSiteAddress {
    static let httpPort = 8080
    static let httpsPort = 8443

    /// The browser-facing URL. Portless mode omits the port (the relay owns 80/443).
    static func url(
        domain: SiteDomain,
        https: Bool,
        portMode: SettingsData.LocalDomainsSettings.PortMode
    ) -> URL? {
        var components = URLComponents()
        components.scheme = https ? "https" : "http"
        components.host = domain.value
        if portMode == .highPorts {
            components.port = https ? httpsPort : httpPort
        }
        components.path = "/"
        return components.url
    }
}

@MainActor
protocol NginxApplying: AnyObject {
    var prefix: NginxPrefix { get }
    var isRunning: Bool { get }
    func apply(executableURL: URL, sites: [NginxSiteConfiguration], listenPorts: Set<Int>) async throws
    func stop() async
}

@MainActor
protocol PHPFPMRunning: AnyObject {
    func start(_ runtime: PHPFPMRuntimeConfiguration) async throws
    func stop() async
}

extension NginxController: NginxApplying {}
extension PHPFPMController: PHPFPMRunning {}

/// Composes the real per-site pipeline: resolve the document root, issue a certificate, start one
/// PHP-FPM master per PHP site, and reconcile every active site into the single app-managed nginx.
/// Sites are keyed by workspace so each workspace's coordinator can drive its own slice.
@MainActor
final class LocalSitePipeline {
    struct ActiveSite {
        let siteID: String
        let domain: SiteDomain
        let nginxSite: NginxSiteConfiguration
        let fpm: (any PHPFPMRunning)?
        let safeRoot: URL
    }

    typealias RuntimeLoader = @MainActor () async -> [InstalledRuntime]
    typealias FPMFactory = @MainActor () -> any PHPFPMRunning

    let tooling: LocalServerTooling
    let authority: any CertificateProviding
    let nginx: any NginxApplying
    let registry: SiteRegistry
    let catalog: PHPFPMRuntimeCatalog
    let runtimeLoader: RuntimeLoader
    let makeFPM: FPMFactory
    let fileManager: FileManager
    let tempDirectory: URL
    let httpPort: Int
    let httpsPort: Int

    var activeSites: [String: ActiveSite] = [:]

    init(
        tooling: LocalServerTooling,
        authority: any CertificateProviding,
        nginx: any NginxApplying,
        registry: SiteRegistry,
        catalog: PHPFPMRuntimeCatalog? = nil,
        runtimeLoader: RuntimeLoader? = nil,
        makeFPM: FPMFactory? = nil,
        fileManager: FileManager = .default,
        tempDirectory: URL = URL(filePath: "/tmp", directoryHint: .isDirectory),
        httpPort: Int = LocalSiteAddress.httpPort,
        httpsPort: Int = LocalSiteAddress.httpsPort
    ) {
        self.tooling = tooling
        self.authority = authority
        self.nginx = nginx
        self.registry = registry
        self.catalog = catalog ?? PHPFPMRuntimeCatalog()
        self.runtimeLoader = runtimeLoader ?? {
            guard let provider = AppServices.runtimeManager.provider(for: .php) else {
                return []
            }
            return await provider.installedVersions()
        }
        self.makeFPM = makeFPM ?? { PHPFPMController() }
        self.fileManager = fileManager
        self.tempDirectory = tempDirectory
        self.httpPort = httpPort
        self.httpsPort = httpsPort
    }

    var runningSiteCount: Int {
        activeSites.count
    }

    func isSiteActive(workspaceURL: URL) -> Bool {
        activeSites[SiteRegistration.siteID(forWorkspaceURL: workspaceURL)] != nil
    }
}

/// Bridges the workspace coordinator's runner to the shared ``LocalSitePipeline``.
@MainActor
final class SitePipelineOperations: LocalSiteOperations {
    let workspaceURL: URL

    private let pipeline: LocalSitePipeline
    private let loadSite: () -> LocalSiteSettings
    private let prepare: () throws -> Void
    private let upstream: (any ProxyUpstreamRunning)?
    private let readiness: PortReadinessWaiter
    private let upstreamReadinessTimeout: Duration
    private var startedUpstream = false

    init(
        workspaceURL: URL,
        pipeline: LocalSitePipeline,
        loadSite: @escaping () -> LocalSiteSettings,
        prepare: @escaping () throws -> Void,
        upstream: (any ProxyUpstreamRunning)? = nil,
        readiness: PortReadinessWaiter? = nil,
        upstreamReadinessTimeout: Duration = .seconds(10)
    ) {
        self.workspaceURL = workspaceURL
        self.pipeline = pipeline
        self.loadSite = loadSite
        self.prepare = prepare
        self.upstream = upstream
        self.readiness = readiness ?? PortReadinessWaiter()
        self.upstreamReadinessTimeout = upstreamReadinessTimeout
    }

    func start(rollback: SiteRollback) async throws {
        try prepare()
        let site = loadSite()
        try await startUpstreamIfNeeded(site)
        do {
            try await pipeline.start(workspaceURL: workspaceURL, site: site, rollback: rollback)
        } catch {
            await stopUpstream()
            throw error
        }
    }

    func stop() async {
        await pipeline.stop(workspaceURL: workspaceURL)
        await stopUpstream()
    }

    func reload() async throws {
        try prepare()
        let site = loadSite()
        await stopUpstream()
        try await startUpstreamIfNeeded(site)
        do {
            try await pipeline.reload(workspaceURL: workspaceURL, site: site)
        } catch {
            await stopUpstream()
            throw error
        }
    }

    private func startUpstreamIfNeeded(_ site: LocalSiteSettings) async throws {
        guard let upstream,
              site.handler == .proxy,
              !site.proxy.startCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        try await upstream.start(site: site, workspaceURL: workspaceURL)
        let result = await readiness.wait(
            port: site.proxy.port,
            timeout: upstreamReadinessTimeout,
            isAlive: { upstream.isRunning }
        )
        switch result {
        case .ready:
            startedUpstream = true
        case .cancelled:
            upstream.stop()
            throw CancellationError()
        case .timedOut, .upstreamExited:
            let output = upstream.outputTail ?? ""
            upstream.stop()
            throw LocalSiteError.upstreamNotReady(port: site.proxy.port, output: output)
        }
    }

    private func stopUpstream() async {
        guard startedUpstream else {
            return
        }
        startedUpstream = false
        upstream?.stop()
    }
}
