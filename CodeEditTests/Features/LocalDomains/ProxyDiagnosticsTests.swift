import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct ProxyDiagnosticsTests {
    @Test
    func rendersReport() {
        let report = ProxyDiagnosticsReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "1.2.3 (45)",
            macOSVersion: "Version 15.0",
            proxyRoot: "~/.codeedit/proxy",
            portMode: "High ports (8080/8443)",
            tools: ["nginx: 1.29.4 (/opt/homebrew/bin/nginx)"],
            authority: "trusted",
            siteDomains: ["app.localhost", "api.localhost"],
            recentErrors: ["[error] boom"],
            lastError: "certificate failed"
        )

        let text = report.rendered()

        #expect(text.contains("CodeEdit Local Domains Diagnostics"))
        #expect(text.contains("Generated: 1970-01-01T00:00:00Z"))
        #expect(text.contains("CodeEdit: 1.2.3 (45)"))
        #expect(text.contains("Proxy root: ~/.codeedit/proxy"))
        #expect(text.contains("Port mode: High ports (8080/8443)"))
        #expect(text.contains("nginx: 1.29.4 (/opt/homebrew/bin/nginx)"))
        #expect(text.contains("Certificate authority: trusted"))
        #expect(text.contains("Registered sites: 2"))
        #expect(text.contains("  - api.localhost"))
        #expect(text.contains("  [error] boom"))
        #expect(text.contains("Last action error: certificate failed"))
    }

    @Test
    func rendersEmptySections() {
        let report = ProxyDiagnosticsReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "1",
            macOSVersion: "x",
            proxyRoot: "~",
            portMode: "High ports",
            tools: [],
            authority: "not created",
            siteDomains: [],
            recentErrors: [],
            lastError: nil
        )

        let text = report.rendered()

        #expect(text.contains("Registered sites: none"))
        #expect(text.contains("Recent nginx errors:\n  (none)"))
        #expect(!text.contains("Last action error"))
    }

    @Test
    func redactsHomeQueriesAndSecrets() {
        let home = URL(filePath: "/Users/example")

        let redacted = LocalDomainsDiagnostics.redact(
            "/Users/example/project/index.php?token=abc&x=1 password=secret",
            home: home
        )

        #expect(redacted.hasPrefix("~/project/index.php"))
        #expect(!redacted.contains("/Users/example"))
        #expect(!redacted.contains("token=abc"))
        #expect(!redacted.contains("password=secret"))
        #expect(redacted.contains("password=<redacted>"))
    }

    @Test
    func reportGathersToolsSitesAndErrors() async throws {
        try await withTempDir { dir in
            let fixture = try makeReportFixture(in: dir)

            let text = await fixture.model.report(
                portMode: .highPorts,
                lastError: "failed in \(fixture.home.path(percentEncoded: false))"
            )

            #expect(text.contains("Homebrew: Homebrew 4.5.0"))
            #expect(text.contains("nginx: 1.29.4"))
            #expect(text.contains("mkcert: v1.4.4"))
            #expect(text.contains("Certificate authority: trusted"))
            #expect(text.contains("Registered sites: 1"))
            #expect(text.contains("Proxy root: ~/proxy"))
            #expect(text.contains("password=<redacted>"))
            #expect(!text.contains("token=abc"))
            #expect(!text.contains(fixture.home.path(percentEncoded: false)))
            #expect(text.contains("Last action error: failed in ~"))
        }
    }

    private func makeReportFixture(in dir: URL) throws -> (model: LocalDomainsDiagnostics, home: URL) {
        let home = dir.appending(path: "home", directoryHint: .isDirectory)
        let prefix = NginxPrefix(root: home.appending(path: "proxy/nginx", directoryHint: .isDirectory))
        try prefix.createDirectories()
        try """
        \(home.path(percentEncoded: false))/project/index.php failed
        GET /index.php?token=abc
        password=hunter2
        """.write(to: prefix.errorLogURL, atomically: true, encoding: .utf8)

        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.5.0", status: 0), for: "brew --version")
        shell.setResult(
            ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0),
            for: "command -v mkcert"
        )
        shell.setResult(ShellResult(output: "v1.4.4", status: 0), for: "mkcert -version")

        let locator = FakeNginxLocator()
        locator.installation = NginxInstallation(
            executableURL: URL(filePath: "/opt/homebrew/bin/nginx"),
            version: "1.29.4",
            prefixURL: nil
        )
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: true)
        let registry = SiteRegistry()
        try registry.register(SiteRegistration(
            siteID: "a",
            domain: try SiteDomain("app.localhost"),
            workspaceURL: URL(filePath: "/tmp/app")
        ))
        let model = LocalDomainsDiagnostics(
            prefix: prefix,
            authorityPaths: CertificateAuthorityPaths(
                root: home.appending(path: "proxy/ca"),
                certificates: home.appending(path: "proxy/certs")
            ),
            tooling: LocalServerTooling(shell: shell, nginxLocator: locator),
            authority: authority,
            registry: registry,
            homeDirectory: home,
            timeSource: FakeTimeSource(now: Date(timeIntervalSince1970: 0)),
            appVersion: { "1.2.3 (45)" },
            macOSVersion: { "Version 15.0" }
        )
        return (model, home)
    }

    @Test
    func resetRemovesGeneratedStateAndKeepsAuthority() async throws {
        try await withTempDir { dir in
            let home = dir.appending(path: "home", directoryHint: .isDirectory)
            let proxy = home.appending(path: "proxy", directoryHint: .isDirectory)
            let prefix = NginxPrefix(root: proxy.appending(path: "nginx", directoryHint: .isDirectory))
            let authorityPaths = CertificateAuthorityPaths(
                root: proxy.appending(path: "ca", directoryHint: .isDirectory),
                certificates: proxy.appending(path: "certs", directoryHint: .isDirectory)
            )
            try prefix.createDirectories()
            try FileManager.default.createDirectory(
                at: prefix.generationDirectory(named: "1"),
                withIntermediateDirectories: true
            )
            try "server {}".write(
                to: prefix.generationDirectory(named: "1").appending(path: "nginx.conf"),
                atomically: true,
                encoding: .utf8
            )
            try "1234".write(to: prefix.pidURL, atomically: true, encoding: .utf8)
            try "types {}".write(to: prefix.mimeTypesURL, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(
                at: authorityPaths.certificates,
                withIntermediateDirectories: true
            )
            try "cert".write(
                to: authorityPaths.certificate(for: "app.localhost"),
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.createDirectory(
                at: authorityPaths.root,
                withIntermediateDirectories: true
            )
            try "root".write(to: authorityPaths.rootCertificate, atomically: true, encoding: .utf8)
            try "keep".write(to: proxy.appending(path: "lock"), atomically: true, encoding: .utf8)

            let stopper = FakeProxyProcessStopper()
            let model = makeModel(prefix: prefix, authorityPaths: authorityPaths, home: home, stopper: stopper)

            try await model.resetGeneratedState()

            #expect(stopper.stoppedPIDURLs == [prefix.pidURL])
            #expect(!FileManager.default.fileExists(
                atPath: prefix.generationDirectory(named: "1").path
            ))
            #expect(!FileManager.default.fileExists(atPath: prefix.mimeTypesURL.path))
            #expect(!FileManager.default.fileExists(atPath: prefix.currentSymlink.path))
            #expect(!FileManager.default.fileExists(atPath: authorityPaths.certificates.path))
            #expect(FileManager.default.fileExists(atPath: authorityPaths.rootCertificate.path))
            #expect(FileManager.default.fileExists(atPath: proxy.appending(path: "lock").path))
            #expect(FileManager.default.fileExists(atPath: prefix.logsDirectory.path))
            #expect(FileManager.default.fileExists(atPath: prefix.runDirectory.path))
        }
    }

    @Test
    func resetLeavesFilesWhenProcessCannotStop() async throws {
        try await withTempDir { dir in
            let home = dir.appending(path: "home", directoryHint: .isDirectory)
            let prefix = NginxPrefix(root: home.appending(path: "proxy/nginx", directoryHint: .isDirectory))
            let authorityPaths = CertificateAuthorityPaths(
                root: home.appending(path: "proxy/ca"),
                certificates: home.appending(path: "proxy/certs")
            )
            try prefix.createDirectories()
            try "1234".write(to: prefix.pidURL, atomically: true, encoding: .utf8)

            let stopper = FakeProxyProcessStopper()
            stopper.error = ProxyStateResetError.processStillRunning(pid: 1234)
            let model = makeModel(prefix: prefix, authorityPaths: authorityPaths, home: home, stopper: stopper)

            await #expect(throws: ProxyStateResetError.processStillRunning(pid: 1234)) {
                try await model.resetGeneratedState()
            }
            #expect(FileManager.default.fileExists(atPath: prefix.root.path))
        }
    }

    private func makeModel(
        prefix: NginxPrefix,
        authorityPaths: CertificateAuthorityPaths,
        home: URL,
        stopper: FakeProxyProcessStopper
    ) -> LocalDomainsDiagnostics {
        LocalDomainsDiagnostics(
            prefix: prefix,
            authorityPaths: authorityPaths,
            tooling: LocalServerTooling(shell: FakeShellRunner(), nginxLocator: FakeNginxLocator()),
            authority: FakeCertificateProvider(),
            registry: SiteRegistry(),
            homeDirectory: home,
            timeSource: FakeTimeSource(),
            stopper: stopper
        )
    }
}

@MainActor
struct NginxPidFileStopperTests {
    @Test
    func doesNothingWithoutPIDFile() async throws {
        try await withTempDir { dir in
            let shell = FakeShellRunner()
            let stopper = NginxPidFileStopper(shell: shell, timeSource: FakeTimeSource(), currentUID: 501)

            try await stopper.stopIfRunning(pidURL: dir.appending(path: "nginx.pid"))

            #expect(shell.runCommands.isEmpty)
        }
    }

    @Test
    func refusesForeignProcess() async throws {
        try await withTempDir { dir in
            let pidURL = try writePID(1234, in: dir)
            let shell = FakeShellRunner()
            shell.handler = { command in
                command.hasPrefix("ps ")
                    ? ShellResult(output: "999999 /opt/homebrew/bin/nginx\n", status: 0)
                    : ShellResult(output: "", status: 0)
            }
            let stopper = NginxPidFileStopper(shell: shell, timeSource: FakeTimeSource(), currentUID: 501)

            await #expect(throws: ProxyStateResetError.processNotOwned(pid: 1234)) {
                try await stopper.stopIfRunning(pidURL: pidURL)
            }
            #expect(!shell.runCommands.contains { $0.hasPrefix("kill -QUIT") })
        }
    }

    @Test
    func refusesNonNginxProcess() async throws {
        try await withTempDir { dir in
            let pidURL = try writePID(1234, in: dir)
            let shell = FakeShellRunner()
            shell.handler = { command in
                command.hasPrefix("ps ")
                    ? ShellResult(output: "501 /usr/bin/python3\n", status: 0)
                    : ShellResult(output: "", status: 0)
            }
            let stopper = NginxPidFileStopper(shell: shell, timeSource: FakeTimeSource(), currentUID: 501)

            await #expect(throws: ProxyStateResetError.processNotNginx(pid: 1234)) {
                try await stopper.stopIfRunning(pidURL: pidURL)
            }
            #expect(!shell.runCommands.contains { $0.hasPrefix("kill -QUIT") })
        }
    }

    @Test
    func stopsOwnedNginxGracefully() async throws {
        try await withTempDir { dir in
            let pidURL = try writePID(1234, in: dir)
            let alive = LockedFlag(true)
            let shell = FakeShellRunner()
            shell.handler = { command in
                if command.hasPrefix("ps ") {
                    return ShellResult(output: "501 /opt/homebrew/bin/nginx\n", status: 0)
                }
                if command == "kill -QUIT 1234" {
                    alive.value = false
                    return ShellResult(output: "", status: 0)
                }
                if command == "kill -0 1234" {
                    return ShellResult(output: "", status: alive.value ? 0 : 1)
                }
                return ShellResult(output: "", status: 0)
            }
            let timeSource = FakeTimeSource()
            let stopper = NginxPidFileStopper(shell: shell, timeSource: timeSource, currentUID: 501)

            try await stopper.stopIfRunning(pidURL: pidURL)

            #expect(shell.runCommands.contains("kill -QUIT 1234"))
            #expect(!shell.runCommands.contains("kill -KILL 1234"))
        }
    }

    @Test
    func escalatesToKillAndReportsStubbornProcess() async throws {
        try await withTempDir { dir in
            let pidURL = try writePID(1234, in: dir)
            let shell = FakeShellRunner()
            shell.handler = { command in
                if command.hasPrefix("ps ") {
                    return ShellResult(output: "501 /opt/homebrew/bin/nginx\n", status: 0)
                }
                if command.hasPrefix("kill ") {
                    return ShellResult(output: "", status: 0)
                }
                return ShellResult(output: "", status: 1)
            }
            let stopper = NginxPidFileStopper(shell: shell, timeSource: FakeTimeSource(), currentUID: 501)

            await #expect(throws: ProxyStateResetError.processStillRunning(pid: 1234)) {
                try await stopper.stopIfRunning(pidURL: pidURL)
            }
            #expect(shell.runCommands.contains("kill -KILL 1234"))
        }
    }

    private func writePID(_ pid: Int32, in directory: URL) throws -> URL {
        let url = directory.appending(path: "nginx.pid")
        try "\(pid)".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@MainActor
final class FakeProxyProcessStopper: ProxyProcessStopping {
    var error: Error?
    private(set) var stoppedPIDURLs: [URL] = []

    func stopIfRunning(pidURL: URL) async throws {
        stoppedPIDURLs.append(pidURL)
        if let error {
            throw error
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        self.storedValue = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
