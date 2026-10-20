import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct LocalSitePipelineTests {
    @Test
    func startStaticSiteAppliesToNginx() async throws {
        try await withTempDir { root in
            let workspace = try makeWorkspace(root)
            let harness = makeHarness(root)
            let rollback = SiteRollback()

            try await harness.pipeline.start(
                workspaceURL: workspace,
                site: makeSite(handler: .staticFiles, https: false),
                rollback: rollback
            )

            #expect(harness.nginx.applyCalls == 1)
            #expect(harness.nginx.isRunning)
            #expect(harness.nginx.appliedSites.count == 1)
            #expect(harness.nginx.appliedSites.first?.serverName == "app.localhost")
            #expect(harness.registry.registration(for: try SiteDomain("app.localhost")) != nil)
            #expect(harness.pipeline.runningSiteCount == 1)
            #expect(rollback.count == 2)
        }
    }

    @Test
    func startPHPSiteStartsFPMWithSafeRoot() async throws {
        try await withTempDir { root in
            let workspace = try makeWorkspace(root)
            let harness = makeHarness(root, phpRuntime: runtime())
            var site = makeSite(handler: .phpFPM, https: false)
            site.documentRoot = "public"
            site.routing = .frontController

            try await harness.pipeline.start(
                workspaceURL: workspace,
                site: site,
                rollback: SiteRollback()
            )

            let configuration = try #require(harness.fpm.configurations.first)
            let pool = configuration.pool
            #expect(harness.fpm.configurations.count == 1)
            let tempPath = try FileManager.default.destinationOfSymbolicLink(atPath: pool.documentRootPath)
            let tempPrefix = root.appending(path: "tmp").path(percentEncoded: false)
            #expect(pool.socketPath.hasPrefix(tempPrefix + "/ce-fpm-"))
            #expect(pool.documentRootPath.hasPrefix(tempPrefix + "/ce-root-"))
            #expect(
                URL(filePath: tempPath).resolvingSymlinksInPath().path(percentEncoded: false)
                    == workspace.appending(path: "public").resolvingSymlinksInPath()
                        .path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        .withLeadingSlash
            )
            guard case .phpFPM(let socketPath) = harness.nginx.appliedSites.first?.upstream else {
                Issue.record("Expected a PHP-FPM upstream")
                return
            }
            #expect(socketPath == pool.socketPath)
        }
    }

    @Test
    func httpsWithoutTrustedAuthorityThrows() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root)
            harness.authority.status = .present(trusted: false)

            await #expect(throws: LocalSiteError.certificateUntrusted) {
                try await harness.pipeline.start(
                    workspaceURL: try makeWorkspace(root),
                    site: makeSite(handler: .staticFiles, https: true),
                    rollback: SiteRollback()
                )
            }
            #expect(harness.nginx.applyCalls == 0)
            #expect(harness.pipeline.runningSiteCount == 0)
        }
    }

    @Test
    func stoppingLastSiteStopsNginx() async throws {
        try await withTempDir { root in
            let workspace = try makeWorkspace(root)
            let harness = makeHarness(root)
            try await harness.pipeline.start(
                workspaceURL: workspace,
                site: makeSite(handler: .staticFiles, https: false),
                rollback: SiteRollback()
            )

            await harness.pipeline.stop(workspaceURL: workspace)

            #expect(harness.nginx.stopCalls == 1)
            #expect(harness.pipeline.runningSiteCount == 0)
            #expect(harness.registry.registration(for: try SiteDomain("app.localhost")) == nil)
        }
    }

    @Test
    func reloadReplacesDomain() async throws {
        try await withTempDir { root in
            let workspace = try makeWorkspace(root)
            let harness = makeHarness(root)
            try await harness.pipeline.start(
                workspaceURL: workspace,
                site: makeSite(handler: .staticFiles, https: false),
                rollback: SiteRollback()
            )

            try await harness.pipeline.reload(
                workspaceURL: workspace,
                site: makeSite(domain: "next.localhost", handler: .staticFiles, https: false)
            )

            #expect(harness.nginx.appliedSites.map(\.serverName) == ["next.localhost"])
            #expect(harness.registry.registration(for: try SiteDomain("app.localhost")) == nil)
            #expect(harness.registry.registration(for: try SiteDomain("next.localhost")) != nil)
        }
    }

    @Test
    func missingPHPRuntimeThrows() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root)

            await #expect(throws: LocalSiteError.self) {
                try await harness.pipeline.start(
                    workspaceURL: try makeWorkspace(root),
                    site: makeSite(handler: .phpFPM, https: false),
                    rollback: SiteRollback()
                )
            }
            #expect(harness.nginx.applyCalls == 0)
            #expect(harness.fpm.configurations.isEmpty)
        }
    }

    @Test
    func reconcileFailureRestoresPreviousSites() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root)
            try await harness.pipeline.start(
                workspaceURL: try makeWorkspace(root, name: "one"),
                site: makeSite(handler: .staticFiles, https: false),
                rollback: SiteRollback()
            )
            harness.nginx.applyError = NginxControllerError.portInUse(8080)

            await #expect(throws: LocalSiteError.portInUse(8080)) {
                try await harness.pipeline.start(
                    workspaceURL: try makeWorkspace(root, name: "two"),
                    site: makeSite(domain: "two.localhost", handler: .staticFiles, https: false),
                    rollback: SiteRollback()
                )
            }
            #expect(harness.pipeline.runningSiteCount == 1)
            #expect(harness.registry.registration(for: try SiteDomain("two.localhost")) == nil)
        }
    }

    @Test
    func documentRootOutsideWorkspaceIsRejected() async throws {
        try await withTempDir { root in
            let workspace = try makeWorkspace(root)
            let outside = root.appending(path: "outside", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            var site = makeSite(handler: .staticFiles, https: false)
            site.documentRoot = "../outside"

            await #expect(throws: LocalSiteError.documentRootOutsideWorkspace) {
                try await harness(root).pipeline.start(
                    workspaceURL: workspace,
                    site: site,
                    rollback: SiteRollback()
                )
            }
        }
    }

    @Test
    func frontControllerRequiresEntryFile() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root, phpRuntime: runtime())
            var site = makeSite(handler: .phpFPM, https: false)
            site.documentRoot = "public"
            site.routing = .frontController
            site.entryFile = "missing.php"

            await #expect(throws: LocalSiteError.self) {
                try await harness.pipeline.start(
                    workspaceURL: try makeWorkspace(root),
                    site: site,
                    rollback: SiteRollback()
                )
            }
            #expect(harness.fpm.configurations.isEmpty)
        }
    }
}

private extension String {
    var withLeadingSlash: String { "/" + self }
}

extension LocalSitePipelineTests {

    private struct Harness {
        let pipeline: LocalSitePipeline
        let nginx: FakeNginx
        let fpm: FakeFPM
        let registry: SiteRegistry
        let authority: FakeCertificateProvider
    }

    private func harness(_ root: URL) -> Harness {
        makeHarness(root)
    }

    private func makeHarness(_ root: URL, phpRuntime: LocalSiteRuntime? = nil) -> Harness {
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: true)
        let registry = SiteRegistry()
        let nginx = FakeNginx(prefix: NginxPrefix(root: root.appending(path: "nginx")))
        let fpm = FakeFPM()
        let detector = FakePHPFPMDetector()
        if let phpRuntime {
            detector.statuses[phpRuntime.runtime.id] = .available(phpRuntime.installation)
        }
        let catalog = PHPFPMRuntimeCatalog(detector: detector)
        let pipeline = LocalSitePipeline(
            tooling: tooling(),
            authority: authority,
            nginx: nginx,
            registry: registry,
            catalog: catalog,
            runtimeLoader: { phpRuntime.map { [$0.runtime] } ?? [] },
            makeFPM: { fpm },
            tempDirectory: root.appending(path: "tmp", directoryHint: .isDirectory)
        )
        try? FileManager.default.createDirectory(
            at: root.appending(path: "tmp", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return Harness(pipeline: pipeline, nginx: nginx, fpm: fpm, registry: registry, authority: authority)
    }

    private func tooling() -> LocalServerTooling {
        let shell = FakeShellRunner()
        shell.handler = { command in
            if command == "command -v nginx" {
                return ShellResult(output: "/opt/homebrew/bin/nginx", status: 0)
            }
            if command == "nginx -v" {
                return ShellResult(output: "nginx version: nginx/1.29.4", status: 0)
            }
            return ShellResult(output: "", status: 1)
        }
        let locator = FakeNginxLocator()
        locator.installation = NginxInstallation(
            executableURL: URL(filePath: "/opt/homebrew/bin/nginx"),
            version: "1.29.4",
            prefixURL: nil
        )
        return LocalServerTooling(shell: shell, nginxLocator: locator)
    }

    private func makeWorkspace(_ root: URL, name: String = "workspace") throws -> URL {
        let workspace = root.appending(path: name, directoryHint: .isDirectory)
        let publicDir = workspace.appending(path: "public", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: publicDir, withIntermediateDirectories: true)
        try Data("<?php echo 'ok';".utf8).write(to: publicDir.appending(path: "index.php"))
        return workspace
    }

    private func makeSite(
        domain: String = "app.localhost",
        handler: LocalSiteHandler,
        https: Bool
    ) -> LocalSiteSettings {
        var site = LocalSiteSettings()
        site.domain = domain
        site.handler = handler
        site.https = https
        return site
    }

    private func runtime() -> LocalSiteRuntime {
        let installed = InstalledRuntime(
            kind: .php,
            version: "8.4.12",
            source: .brew,
            executableDirectory: URL(filePath: "/opt/php/8.4.12/bin", directoryHint: .isDirectory)
        )
        return LocalSiteRuntime(
            runtime: installed,
            installation: PHPFPMInstallation(
                executableURL: installed.executable(relativePath: "sbin/php-fpm"),
                version: "8.4.12"
            )
        )
    }
}
