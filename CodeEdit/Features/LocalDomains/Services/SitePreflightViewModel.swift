import Foundation

/// Drives the Local Domain preflight checklist: probes host tools, the app-owned CA, and installed
/// PHP runtimes, then performs the install/trust actions the checklist offers.
@MainActor
final class SitePreflightViewModel: ObservableObject {
    typealias RuntimeLoader = @MainActor () async -> [InstalledRuntime]

    @Published private(set) var items: [SitePreflightItem] = SitePreflightKind.allCases.map {
        SitePreflightItem(kind: $0, status: .checking)
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyKind: SitePreflightKind?
    @Published private(set) var errorMessage: String?

    private let tooling: LocalServerTooling
    private let authority: any CertificateProviding
    private let catalog: PHPFPMRuntimeCatalog
    private let loadRuntimes: RuntimeLoader

    init(
        tooling: LocalServerTooling? = nil,
        authority: (any CertificateProviding)? = nil,
        catalog: PHPFPMRuntimeCatalog? = nil,
        loadRuntimes: RuntimeLoader? = nil
    ) {
        let tooling = tooling ?? AppServices.localProxy.tooling
        self.tooling = tooling
        self.authority = authority ?? CertificateAuthority(tooling: tooling)
        self.catalog = catalog ?? PHPFPMRuntimeCatalog()
        self.loadRuntimes = loadRuntimes ?? {
            guard let provider = AppServices.runtimeManager.provider(for: .php) else {
                return []
            }
            return await provider.installedVersions()
        }
    }

    var brewAvailable: Bool {
        tooling.brew.isInstalled
    }

    var mkcertInstalled: Bool {
        tooling.mkcert.isInstalled
    }

    var isBusy: Bool {
        isRefreshing || busyKind != nil
    }

    var needsHomebrew: Bool {
        guard !tooling.brew.isInstalled else {
            return false
        }
        return items.contains {
            ($0.kind == .nginx || $0.kind == .mkcert) && $0.status.isActionRequired
        }
    }

    func refresh(site: LocalSiteSettings) async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true

        await tooling.refresh()
        let authorityStatus = await authority.authorityStatus()
        let installed = await loadRuntimes()
        let usable = await catalog.usableRuntimes(from: installed)

        items = SitePreflight.items(SitePreflightInputs(
            nginx: tooling.nginx,
            mkcert: tooling.mkcert,
            phpRuntimes: usable,
            pinnedPHP: site.phpVersion,
            authority: authorityStatus,
            usesHTTPS: site.https
        ))
        isRefreshing = false
    }

    func install(_ kind: SitePreflightKind, site: LocalSiteSettings) async {
        guard kind != .phpFPM, busyKind == nil else {
            return
        }
        busyKind = kind
        errorMessage = nil

        do {
            switch kind {
            case .nginx:
                try await tooling.install(.nginx)
            case .mkcert:
                try await tooling.install(.mkcert)
            case .certificate:
                try await authority.trustAuthority()
            case .phpFPM:
                break
            }
        } catch {
            errorMessage = Self.message(for: error)
        }

        busyKind = nil
        await refresh(site: site)
    }

    private static func message(for error: Error) -> String {
        guard let localized = error as? LocalizedError else {
            return error.localizedDescription
        }
        guard let suggestion = localized.recoverySuggestion, !suggestion.isEmpty else {
            return localized.localizedDescription
        }
        return "\(localized.localizedDescription) \(suggestion)"
    }
}
