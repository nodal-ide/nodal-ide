import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct SitePipelineOperationsTests {
    @Test
    func startRunsUpstreamBeforeProxySite() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root)
            let site = makeProxySite()
            let operations = makeOperations(harness: harness, site: site)

            try await operations.start(rollback: SiteRollback())

            #expect(harness.upstream.startCalls == 1)
            #expect(harness.upstream.isRunning)
            #expect(harness.nginx.isRunning)
            guard case .proxy(let configuration) = harness.nginx.appliedSites.first?.upstream else {
                Issue.record("Expected a proxy upstream")
                return
            }
            #expect(configuration.upstreamPort == 9000)

            await operations.stop()

            #expect(harness.upstream.stopCalls == 1)
            #expect(harness.pipeline.runningSiteCount == 0)
        }
    }

    @Test
    func startSkipsUpstreamWithoutCommand() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root)
            var site = makeProxySite()
            site.proxy.startCommand = ""
            let operations = makeOperations(harness: harness, site: site)

            try await operations.start(rollback: SiteRollback())
            await operations.stop()

            #expect(harness.upstream.startCalls == 0)
            #expect(harness.upstream.stopCalls == 0)
        }
    }

    @Test
    func failedSiteStartStopsTheUpstreamWeStarted() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root)
            harness.authority.status = .present(trusted: false)
            var site = makeProxySite()
            site.https = true
            let operations = makeOperations(harness: harness, site: site)

            await #expect(throws: LocalSiteError.certificateUntrusted) {
                try await operations.start(rollback: SiteRollback())
            }
            #expect(harness.upstream.startCalls == 1)
            #expect(harness.upstream.stopCalls == 1)
            #expect(!harness.upstream.isRunning)
        }
    }

    @Test
    func reloadRestartsTheUpstream() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root)
            let site = makeProxySite()
            let operations = makeOperations(harness: harness, site: site)

            try await operations.start(rollback: SiteRollback())
            try await operations.reload()

            #expect(harness.upstream.startCalls == 2)
            #expect(harness.upstream.stopCalls == 1)
            #expect(harness.upstream.isRunning)
            #expect(harness.pipeline.runningSiteCount == 1)
        }
    }

    @Test
    func readinessFailureStopsUpstreamAndReportsOutput() async throws {
        try await withTempDir { root in
            let harness = makeHarness(root, probeResults: [false])
            harness.upstream.outputTail = "Error: port already in use"
            let operations = makeOperations(harness: harness, site: makeProxySite())

            do {
                try await operations.start(rollback: SiteRollback())
                Issue.record("Expected the start to fail")
            } catch let error as LocalSiteError {
                guard case let .upstreamNotReady(port, output) = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
                #expect(port == 9000)
                #expect(output == "Error: port already in use")
            }
            #expect(harness.upstream.stopCalls == 1)
            #expect(harness.nginx.applyCalls == 0)
        }
    }

    @Test
    func workingDirectoryMustStayInsideTheProject() throws {
        let workspace = URL(filePath: "/tmp/project", directoryHint: .isDirectory)

        let resolved = try TaskManagerProxyUpstream.workingDirectory(
            for: "server",
            workspaceURL: workspace
        )
        #expect(
            resolved.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                == "tmp/project/server"
        )

        #expect(throws: LocalSiteError.self) {
            try TaskManagerProxyUpstream.workingDirectory(for: "../outside", workspaceURL: workspace)
        }
    }
}

extension SitePipelineOperationsTests {
    private struct Harness {
        let workspace: URL
        let pipeline: LocalSitePipeline
        let nginx: FakeNginx
        let upstream: FakeProxyUpstream
        let authority: FakeCertificateProvider
        let readiness: PortReadinessWaiter
    }

    private func makeOperations(harness: Harness, site: LocalSiteSettings) -> SitePipelineOperations {
        SitePipelineOperations(
            workspaceURL: harness.workspace,
            pipeline: harness.pipeline,
            loadSite: { site },
            prepare: {},
            upstream: harness.upstream,
            readiness: harness.readiness,
            upstreamReadinessTimeout: .milliseconds(100)
        )
    }

    private func makeProxySite() -> LocalSiteSettings {
        var site = LocalSiteSettings()
        site.domain = "app.localhost"
        site.handler = .proxy
        site.https = false
        site.proxy.port = 9000
        site.proxy.startCommand = "npm run dev"
        return site
    }

    private func makeHarness(_ root: URL, probeResults: [Bool] = [true]) -> Harness {
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: true)
        let workspace = root.appending(path: "workspace", directoryHint: .isDirectory)
        let server = workspace.appending(path: "server", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: server, withIntermediateDirectories: true)
        let nginx = FakeNginx(prefix: NginxPrefix(root: root.appending(path: "nginx")))
        let upstream = FakeProxyUpstream()
        let readiness = PortReadinessWaiter(
            probe: FakePortProber(results: probeResults),
            timeSource: FakeTimeSource()
        )
        let pipeline = LocalSitePipeline(
            tooling: tooling(),
            authority: authority,
            nginx: nginx,
            registry: SiteRegistry(),
            runtimeLoader: { [] },
            makeFPM: { FakeFPM() },
            tempDirectory: root.appending(path: "tmp", directoryHint: .isDirectory)
        )
        try? FileManager.default.createDirectory(
            at: root.appending(path: "tmp", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return Harness(
            workspace: workspace,
            pipeline: pipeline,
            nginx: nginx,
            upstream: upstream,
            authority: authority,
            readiness: readiness
        )
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
}
