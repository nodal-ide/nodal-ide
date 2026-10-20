import Foundation

extension LocalSitePipeline {
    func start(
        workspaceURL: URL,
        site: LocalSiteSettings,
        rollback: SiteRollback
    ) async throws {
        let siteID = SiteRegistration.siteID(forWorkspaceURL: workspaceURL)
        if let existing = activeSites.removeValue(forKey: siteID) {
            await existing.fpm?.stop()
            removeSafeRoot(existing.safeRoot)
        }

        let domain = try resolveDomain(site)
        let documentRoot = try resolveDocumentRoot(site, workspaceURL: workspaceURL)
        try registerSite(siteID: siteID, domain: domain, workspaceURL: workspaceURL, rollback: rollback)

        await tooling.refresh()

        let safeRoot = try makeSafeRoot(siteID: siteID, documentRoot: documentRoot)
        rollback.register("remove document root link") { [weak self] in
            self?.removeSafeRoot(safeRoot)
        }

        let prepared = try await prepareUpstream(
            site: site,
            siteID: siteID,
            safeRoot: safeRoot,
            rollback: rollback
        )
        let tls = try await tlsConfiguration(for: site, domain: domain)
        let nginxSite = makeNginxSite(site: site, domain: domain, safeRoot: safeRoot, prepared: prepared, tls: tls)

        activeSites[siteID] = ActiveSite(
            siteID: siteID,
            domain: domain,
            nginxSite: nginxSite,
            fpm: prepared.fpm,
            safeRoot: safeRoot
        )

        do {
            try await reconcile()
        } catch {
            await removeSite(siteID: siteID, reconcile: false)
            try? await reconcile()
            throw error
        }
    }

    func stop(workspaceURL: URL) async {
        let siteID = SiteRegistration.siteID(forWorkspaceURL: workspaceURL)
        await removeSite(siteID: siteID, reconcile: true)
    }

    func reload(workspaceURL: URL, site: LocalSiteSettings) async throws {
        await stop(workspaceURL: workspaceURL)
        let rollback = SiteRollback()
        do {
            try await start(workspaceURL: workspaceURL, site: site, rollback: rollback)
        } catch {
            await rollback.run()
            throw error
        }
    }

    func shutdown() async {
        let sites = Array(activeSites.values)
        activeSites.removeAll()
        for site in sites {
            await site.fpm?.stop()
            removeSafeRoot(site.safeRoot)
        }
        await nginx.stop()
        registry.removeAll()
    }

    func registerSite(
        siteID: String,
        domain: SiteDomain,
        workspaceURL: URL,
        rollback: SiteRollback
    ) throws {
        do {
            try registry.register(SiteRegistration(
                siteID: siteID,
                domain: domain,
                workspaceURL: workspaceURL
            ))
        } catch let error as SiteRegistryError {
            if case .domainInUse(let owner, _) = error {
                throw LocalSiteError.domainInUse(owner.value)
            }
            throw LocalSiteError.processFailed(error.localizedDescription)
        }
        rollback.register("unregister site") { [weak self] in
            self?.registry.unregister(siteID: siteID)
        }
    }

    func removeSite(siteID: String, reconcile: Bool) async {
        guard let site = activeSites.removeValue(forKey: siteID) else {
            return
        }
        registry.unregister(siteID: siteID)
        await site.fpm?.stop()
        removeSafeRoot(site.safeRoot)
        if reconcile {
            try? await self.reconcile()
        }
    }

    func reconcile() async throws {
        guard !activeSites.isEmpty else {
            await nginx.stop()
            return
        }

        await tooling.refresh()
        guard case .installed(let installation) = tooling.nginx else {
            throw LocalSiteError.nginxUnavailable
        }
        try nginx.prefix.createDirectories()

        let sites = activeSites.values.map(\.nginxSite)
        let listenPorts = Set(sites.map(\.listenPort))
            .union(sites.compactMap { $0.tls?.httpsListenPort })
        do {
            try await nginx.apply(
                executableURL: installation.executableURL,
                sites: sites,
                listenPorts: listenPorts
            )
        } catch let error as NginxControllerError {
            if case .portInUse(let port) = error {
                throw LocalSiteError.portInUse(port)
            }
            throw LocalSiteError.processFailed(error.localizedDescription)
        }
    }
}
