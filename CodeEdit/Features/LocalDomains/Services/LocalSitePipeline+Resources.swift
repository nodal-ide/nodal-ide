import Foundation

extension LocalSitePipeline {
    struct PreparedUpstream {
        let upstream: NginxUpstream
        let fpm: (any PHPFPMRunning)?
    }

    func prepareUpstream(
        site: LocalSiteSettings,
        siteID: String,
        safeRoot: URL,
        rollback: SiteRollback
    ) async throws -> PreparedUpstream {
        switch site.handler {
        case .staticFiles:
            return PreparedUpstream(upstream: .staticFiles, fpm: nil)
        case .proxy:
            let port = site.proxy.port
            return PreparedUpstream(
                upstream: .proxy(ProxyConfiguration(
                    upstreamPort: port,
                    externalPort: port,
                    scheme: site.https ? "https" : "http"
                )),
                fpm: nil
            )
        case .phpFPM:
            let started = try await startFPM(
                site: site,
                siteID: siteID,
                documentRoot: safeRoot,
                rollback: rollback
            )
            return PreparedUpstream(
                upstream: .phpFPM(socketPath: started.socketPath),
                fpm: started.controller
            )
        }
    }

    func makeNginxSite(
        site: LocalSiteSettings,
        domain: SiteDomain,
        safeRoot: URL,
        prepared: PreparedUpstream,
        tls: NginxTLSSiteConfiguration?
    ) -> NginxSiteConfiguration {
        let logs = nginx.prefix.logsDirectory
        return NginxSiteConfiguration(
            serverName: domain.value,
            listenPort: httpPort,
            documentRootPath: safeRoot.path(percentEncoded: false),
            upstream: prepared.upstream,
            routing: site.routing,
            entryFile: site.entryFile,
            accessLogPath: logs.appending(path: "\(domain.value).access.log").path(percentEncoded: false),
            errorLogPath: logs.appending(path: "\(domain.value).error.log").path(percentEncoded: false),
            tls: tls
        )
    }

    // MARK: - PHP-FPM

    struct StartedFPM {
        let controller: any PHPFPMRunning
        let socketPath: String
    }

    func startFPM(
        site: LocalSiteSettings,
        siteID: String,
        documentRoot: URL,
        rollback: SiteRollback
    ) async throws -> StartedFPM {
        let runtime = try await resolveRuntime(for: site)
        let shortID = String(siteID.prefix(12))
        var tempPath = tempDirectory.path(percentEncoded: false)
        while tempPath.count > 1 && tempPath.hasSuffix("/") {
            tempPath.removeLast()
        }
        let base = tempPath + "/ce-fpm-\(shortID)"
        let socketPath = base + ".sock"
        let pool = PHPFPMPoolConfiguration(
            socketPath: socketPath,
            documentRootPath: documentRoot.path(percentEncoded: false),
            errorLogPath: base + ".log",
            pidPath: base + ".pid",
            environment: PHPFPMEnvironment.allowlist(
                runtimeBinPath: runtime.runtime.executableDirectory.path(percentEncoded: false),
                from: ProcessInfo.processInfo.environment
            )
        )

        let controller = makeFPM()
        do {
            try await controller.start(PHPFPMRuntimeConfiguration(
                executableURL: runtime.installation.executableURL,
                configurationURL: URL(filePath: base + ".conf"),
                pool: pool
            ))
        } catch {
            throw LocalSiteError.processFailed(error.localizedDescription)
        }
        rollback.register("stop php-fpm") { [weak controller] in
            await controller?.stop()
        }
        return StartedFPM(controller: controller, socketPath: socketPath)
    }

    func resolveRuntime(for site: LocalSiteSettings) async throws -> LocalSiteRuntime {
        let runtimes = await runtimeLoader()
        let pinned = site.phpVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pinned, !pinned.isEmpty {
            guard let runtime = await catalog.resolve(version: pinned, from: runtimes) else {
                throw LocalSiteError.phpFPMUnavailable(pinned)
            }
            return runtime
        }

        guard let runtime = await catalog.resolve(version: nil, from: runtimes) else {
            throw LocalSiteError.processFailed("No PHP runtime with PHP-FPM is installed.")
        }
        return runtime
    }

    // MARK: - Certificates

    func tlsConfiguration(
        for site: LocalSiteSettings,
        domain: SiteDomain
    ) async throws -> NginxTLSSiteConfiguration? {
        guard site.https else {
            return nil
        }
        guard await authority.authorityStatus().isTrusted else {
            throw LocalSiteError.certificateUntrusted
        }
        let certificate = try await authority.certificate(for: domain)
        return NginxTLSSiteConfiguration(
            certificatePath: certificate.certificateURL.path(percentEncoded: false),
            privateKeyPath: certificate.privateKeyURL.path(percentEncoded: false),
            httpsListenPort: httpsPort,
            httpListenPort: httpPort,
            externalHTTPSPort: httpsPort
        )
    }

    // MARK: - Paths

    func resolveDomain(_ site: LocalSiteSettings) throws -> SiteDomain {
        do {
            return try SiteDomain(site.domain)
        } catch let error as SiteDomainError {
            throw LocalSiteError.invalidDomain(error)
        }
    }

    func resolveDocumentRoot(_ site: LocalSiteSettings, workspaceURL: URL) throws -> URL {
        let trimmed = site.documentRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty
            ? workspaceURL
            : workspaceURL.appending(path: trimmed, directoryHint: .isDirectory)
        let workspace = workspaceURL.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let workspacePath = normalizedPath(workspace)
        let resolvedPath = normalizedPath(resolved)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalSiteError.documentRootMissing(resolvedPath)
        }
        guard resolvedPath == workspacePath || resolvedPath.hasPrefix(workspacePath + "/") else {
            throw LocalSiteError.documentRootOutsideWorkspace
        }

        if site.handler == .phpFPM && site.routing == .frontController {
            let entry = resolved.appending(path: site.entryFile)
            if !fileManager.fileExists(atPath: entry.path(percentEncoded: false)) {
                throw LocalSiteError.entryFileMissing(entry.path(percentEncoded: false))
            }
        }
        return resolved
    }

    private func normalizedPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    func makeSafeRoot(siteID: String, documentRoot: URL) throws -> URL {
        let link = tempDirectory.appending(path: "ce-root-\(String(siteID.prefix(12)))")
        if fileManager.fileExists(atPath: link.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: link)
        }
        try fileManager.createSymbolicLink(at: link, withDestinationURL: documentRoot)
        return link
    }

    func removeSafeRoot(_ root: URL) {
        try? fileManager.removeItem(at: root)
    }
}
