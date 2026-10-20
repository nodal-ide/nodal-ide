import Foundation
import Testing
@testable import CodeEdit

struct SitePreflightTests {
    @Test
    func readyToolsCarryVersions() {
        let items = SitePreflight.items(SitePreflightInputs(
            nginx: .installed(LocalServerToolInstallation(
                executableURL: URL(filePath: "/opt/homebrew/bin/nginx"),
                version: "1.29.4"
            )),
            mkcert: .installed(LocalServerToolInstallation(
                executableURL: URL(filePath: "/opt/homebrew/bin/mkcert"),
                version: "v1.4.4"
            )),
            phpRuntimes: [availableRuntime(version: "8.4.12")],
            pinnedPHP: nil,
            authority: .present(trusted: true),
            usesHTTPS: true
        ))

        #expect(items.map(\.status) == [
            .ready("nginx 1.29.4"),
            .ready("mkcert v1.4.4"),
            .ready("PHP 8.4.12 with PHP-FPM"),
            .ready("The local certificate authority is trusted.")
        ])
    }

    @Test
    func missingToolsRequireAnAction() {
        let items = SitePreflight.items(SitePreflightInputs(
            nginx: .missing,
            mkcert: .missing,
            phpRuntimes: [],
            pinnedPHP: nil,
            authority: .missing,
            usesHTTPS: true
        ))

        #expect(items[0].status == .actionRequired("nginx is required and was not found."))
        #expect(items[1].status == .actionRequired("mkcert is required and was not found."))
        #expect(items[2].status == .actionRequired("No installed PHP runtime includes PHP-FPM."))
        #expect(items[3].status == .actionRequired("Create and trust the CodeEdit certificate authority."))
    }

    @Test
    func unknownToolsAreChecking() {
        let items = SitePreflight.items(SitePreflightInputs(
            nginx: .unknown,
            mkcert: .unknown,
            phpRuntimes: [],
            pinnedPHP: nil,
            authority: .missing,
            usesHTTPS: true
        ))

        #expect(items[0].status == .checking)
        #expect(items[1].status == .checking)
    }

    @Test
    func pinnedPHPIsCheckedAgainstFPMAvailability() {
        let runtime = availableRuntime(version: "8.4.12")

        let available = SitePreflight.items(SitePreflightInputs(
            nginx: .missing,
            mkcert: .missing,
            phpRuntimes: [runtime],
            pinnedPHP: "8.4.12",
            authority: .missing,
            usesHTTPS: true
        ))
        #expect(available[2].status == .ready("PHP 8.4.12 with PHP-FPM"))

        let unavailable = SitePreflight.items(SitePreflightInputs(
            nginx: .missing,
            mkcert: .missing,
            phpRuntimes: [runtime],
            pinnedPHP: "8.3.6",
            authority: .missing,
            usesHTTPS: true
        ))
        #expect(unavailable[2].status == .actionRequired(
            "PHP 8.3.6 has no PHP-FPM. Install it or choose another version."
        ))
    }

    @Test
    func certificateIsSkippedWhenHTTPSIsOff() {
        let items = SitePreflight.items(SitePreflightInputs(
            nginx: .missing,
            mkcert: .missing,
            phpRuntimes: [],
            pinnedPHP: nil,
            authority: .missing,
            usesHTTPS: false
        ))

        #expect(items[3].status == .skipped("HTTPS is off; the site will be served over HTTP."))
    }

    @Test
    func untrustedAuthorityRequiresTrust() {
        let items = SitePreflight.items(SitePreflightInputs(
            nginx: .missing,
            mkcert: .installed(LocalServerToolInstallation(
                executableURL: URL(filePath: "/opt/homebrew/bin/mkcert"),
                version: "v1.4.4"
            )),
            phpRuntimes: [],
            pinnedPHP: nil,
            authority: .present(trusted: false),
            usesHTTPS: true
        ))

        #expect(items[3].status == .actionRequired(
            "Trust the CodeEdit certificate authority to enable HTTPS."
        ))
    }

    // MARK: - Helpers

    private func availableRuntime(version: String) -> LocalSiteRuntime {
        let runtime = InstalledRuntime(
            kind: .php,
            version: version,
            source: .brew,
            executableDirectory: URL(filePath: "/opt/php/\(version)/bin", directoryHint: .isDirectory)
        )
        return LocalSiteRuntime(
            runtime: runtime,
            installation: PHPFPMInstallation(
                executableURL: runtime.executable(relativePath: "sbin/php-fpm"),
                version: version
            )
        )
    }
}

@MainActor
struct SitePreflightViewModelTests {
    @Test
    func refreshReflectsToolsAuthorityAndRuntime() async {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew\n", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.3.0\n", status: 0), for: "brew --version")
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/mkcert\n", status: 0), for: "command -v mkcert")
        shell.setResult(ShellResult(output: "v1.4.4\n", status: 0), for: "mkcert -version")

        let locator = FakeNginxLocator()
        locator.installation = NginxInstallation(
            executableURL: URL(filePath: "/opt/homebrew/bin/nginx"),
            version: "1.29.4",
            prefixURL: nil
        )
        let authority = FakeCertificateProvider()
        authority.status = .present(trusted: false)
        let runtime = Self.runtime(version: "8.4.12")
        let detector = FakePHPFPMDetector()
        detector.statuses[runtime.id] = .available(PHPFPMInstallation(
            executableURL: runtime.executable(relativePath: "sbin/php-fpm"),
            version: "8.4.12"
        ))
        let model = SitePreflightViewModel(
            tooling: LocalServerTooling(shell: shell, nginxLocator: locator),
            authority: authority,
            catalog: PHPFPMRuntimeCatalog(detector: detector),
            loadRuntimes: { [runtime] }
        )
        var site = LocalSiteSettings()
        site.https = true
        site.phpVersion = "8.4.12"

        await model.refresh(site: site)

        #expect(model.brewAvailable)
        #expect(model.mkcertInstalled)
        #expect(item(.nginx, in: model)?.status == .ready("nginx 1.29.4"))
        #expect(item(.mkcert, in: model)?.status == .ready("mkcert v1.4.4"))
        #expect(item(.phpFPM, in: model)?.status == .ready("PHP 8.4.12 with PHP-FPM"))
        #expect(item(.certificate, in: model)?.status == .actionRequired(
            "Trust the CodeEdit certificate authority to enable HTTPS."
        ))
    }

    @Test
    func trustingTheAuthorityUpdatesTheChecklist() async {
        let authority = FakeCertificateProvider()
        let model = SitePreflightViewModel(
            tooling: LocalServerTooling(shell: FakeShellRunner(), nginxLocator: FakeNginxLocator()),
            authority: authority,
            catalog: PHPFPMRuntimeCatalog(detector: FakePHPFPMDetector()),
            loadRuntimes: { [] }
        )
        var site = LocalSiteSettings()
        site.https = true

        await model.refresh(site: site)
        #expect(item(.certificate, in: model)?.status.isActionRequired == true)

        await model.install(.certificate, site: site)

        #expect(authority.trustCalls == 1)
        #expect(item(.certificate, in: model)?.status == .ready(
            "The local certificate authority is trusted."
        ))
    }

    // MARK: - Helpers

    private func item(_ kind: SitePreflightKind, in model: SitePreflightViewModel) -> SitePreflightItem? {
        model.items.first { $0.kind == kind }
    }

    private static func runtime(version: String) -> InstalledRuntime {
        InstalledRuntime(
            kind: .php,
            version: version,
            source: .brew,
            executableDirectory: URL(filePath: "/opt/php/\(version)/bin", directoryHint: .isDirectory)
        )
    }
}
