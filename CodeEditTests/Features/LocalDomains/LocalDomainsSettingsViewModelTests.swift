import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct LocalDomainsSettingsViewModelTests {
    @Test
    func refreshLoadsToolsAndAuthority() async {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.5.0", status: 0), for: "brew --version")
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0), for: "command -v mkcert")
        shell.setResult(ShellResult(output: "v1.4.4", status: 0), for: "mkcert -version")

        let locator = FakeNginxLocator()
        locator.installation = NginxInstallation(
            executableURL: URL(filePath: "/opt/homebrew/bin/nginx"),
            version: "1.29.4",
            prefixURL: nil
        )
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: true)
        let model = LocalDomainsSettingsViewModel(
            tooling: LocalServerTooling(shell: shell, nginxLocator: locator),
            authority: authority
        )

        await model.refresh()

        #expect(model.hasLoaded)
        #expect(model.brewAvailable)
        #expect(model.nginx.version == "1.29.4")
        #expect(model.mkcert.version == "v1.4.4")
        #expect(model.authority.isTrusted)
        #expect(!model.isBusy)
        #expect(model.errorMessage == nil)
    }

    @Test
    func installsMissingTool() async {
        let state = InstallState()
        let shell = FakeShellRunner()
        shell.handler = { command in
            switch command {
            case "command -v brew":
                return ShellResult(output: "/opt/homebrew/bin/brew", status: 0)
            case "brew --version":
                return ShellResult(output: "Homebrew 4.5.0", status: 0)
            case "brew install mkcert":
                state.markInstalled()
                return ShellResult(output: "installed", status: 0)
            case "command -v mkcert":
                return state.isInstalled
                    ? ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0)
                    : ShellResult(output: "", status: 1)
            case "mkcert -version":
                return state.isInstalled ? ShellResult(output: "v1.4.4", status: 0) : ShellResult(output: "", status: 1)
            default:
                return ShellResult(output: "", status: 1)
            }
        }
        let model = LocalDomainsSettingsViewModel(
            tooling: LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator()),
            authority: FakeCertificateProvider()
        )

        await model.refresh()
        #expect(model.mkcert == .missing)

        await model.install(.mkcert)

        #expect(model.mkcert.version == "v1.4.4")
        #expect(model.busyTool == nil)
        #expect(model.errorMessage == nil)
        #expect(shell.runCommands.contains("brew install mkcert"))
    }

    @Test
    func installWithoutHomebrewShowsError() async {
        let shell = FakeShellRunner()
        let model = LocalDomainsSettingsViewModel(
            tooling: LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator()),
            authority: FakeCertificateProvider()
        )

        await model.refresh()
        await model.install(.nginx)

        #expect(model.errorMessage?.contains("Homebrew") == true)
        #expect(model.busyTool == nil)
        #expect(!shell.runCommands.contains("brew install nginx"))
    }

    @Test
    func installFailureShowsOutput() async {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.5.0", status: 0), for: "brew --version")
        shell.setResult(
            ShellResult(output: "network unavailable", status: 1),
            for: "brew install mkcert"
        )
        let model = LocalDomainsSettingsViewModel(
            tooling: LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator()),
            authority: FakeCertificateProvider()
        )

        await model.refresh()
        await model.install(.mkcert)

        #expect(model.errorMessage?.contains("Installing mkcert failed.") == true)
        #expect(model.errorMessage?.contains("network unavailable") == true)
        #expect(model.busyTool == nil)
        #expect(model.mkcert == .missing)
    }

    @Test
    func diagnosticsReportUsesPortMode() async {
        let authority = FakeCertificateProvider()
        let tooling = LocalServerTooling(shell: FakeShellRunner(), nginxLocator: FakeNginxLocator())
        let diagnostics = LocalDomainsDiagnostics(
            tooling: tooling,
            authority: authority,
            registry: SiteRegistry(),
            timeSource: FakeTimeSource(now: Date(timeIntervalSince1970: 0)),
            appVersion: { "1.2.3 (45)" },
            macOSVersion: { "Version 15.0" }
        )
        let model = LocalDomainsSettingsViewModel(
            tooling: tooling,
            authority: authority,
            diagnostics: diagnostics
        )

        let text = await model.diagnosticsReport(portMode: .privilegedRelay)

        #expect(text.contains("CodeEdit: 1.2.3 (45)"))
        #expect(text.contains("Port mode: Portless (80/443)"))
        #expect(text.contains("Certificate authority: not created"))
    }

    @Test
    func resetGeneratedStateReportsSuccess() async throws {
        try await withTempDir { dir in
            let home = dir.appending(path: "home", directoryHint: .isDirectory)
            let proxy = home.appending(path: "proxy", directoryHint: .isDirectory)
            let prefix = NginxPrefix(root: proxy.appending(path: "nginx", directoryHint: .isDirectory))
            let authorityPaths = CertificateAuthorityPaths(
                root: proxy.appending(path: "ca"),
                certificates: proxy.appending(path: "certs")
            )
            try prefix.createDirectories()
            let authority = FakeCertificateProvider()
            let tooling = LocalServerTooling(shell: FakeShellRunner(), nginxLocator: FakeNginxLocator())
            let stopper = FakeProxyProcessStopper()
            let diagnostics = LocalDomainsDiagnostics(
                prefix: prefix,
                authorityPaths: authorityPaths,
                tooling: tooling,
                authority: authority,
                registry: SiteRegistry(),
                homeDirectory: home,
                timeSource: FakeTimeSource(),
                stopper: stopper
            )
            let model = LocalDomainsSettingsViewModel(
                tooling: tooling,
                authority: authority,
                diagnostics: diagnostics
            )

            await model.resetGeneratedState()

            #expect(model.statusMessage?.contains("removed") == true)
            #expect(!model.isResettingState)
            #expect(stopper.stoppedPIDURLs == [prefix.pidURL])
        }
    }

    @Test
    func trustUpdatesAuthorityState() async {
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: false)
        let model = LocalDomainsSettingsViewModel(
            tooling: LocalServerTooling(shell: FakeShellRunner(), nginxLocator: FakeNginxLocator()),
            authority: authority
        )

        await model.refresh()
        #expect(!model.authority.isTrusted)

        await model.trustAuthority()

        #expect(authority.trustCalls == 1)
        #expect(model.authority.isTrusted)
        #expect(!model.isBusy)
    }

    @Test
    func resetClearsAuthorityState() async {
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: true)
        let model = LocalDomainsSettingsViewModel(
            tooling: LocalServerTooling(shell: FakeShellRunner(), nginxLocator: FakeNginxLocator()),
            authority: authority
        )

        await model.refresh()
        await model.resetAuthority()

        #expect(authority.resetCalls == 1)
        #expect(model.authority == .missing)
        #expect(!model.isBusy)
    }

    @Test
    func trustFailureShowsError() async {
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: false)
        authority.trustResult = .failure(
            CertificateAuthorityError.trustFailed("authorization denied")
        )
        let model = LocalDomainsSettingsViewModel(
            tooling: LocalServerTooling(shell: FakeShellRunner(), nginxLocator: FakeNginxLocator()),
            authority: authority
        )

        await model.refresh()
        await model.trustAuthority()

        #expect(model.errorMessage?.contains("authorization denied") == true)
        #expect(!model.isTrusting)
    }
}

private final class InstallState: @unchecked Sendable {
    private let lock = NSLock()
    private var installed = false

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return installed
    }

    func markInstalled() {
        lock.lock()
        installed = true
        lock.unlock()
    }
}
