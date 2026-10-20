import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct LocalServerToolingTests {
    private func makeNginxInstallation() -> NginxInstallation {
        NginxInstallation(
            executableURL: URL(filePath: "/opt/homebrew/bin/nginx"),
            version: "1.29.4",
            prefixURL: URL(filePath: "/opt/homebrew/var/www")
        )
    }

    @Test
    func detectsInstalledTools() async {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.5.0", status: 0), for: "brew --version")
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0), for: "command -v mkcert")
        shell.setResult(ShellResult(output: "v1.4.4", status: 0), for: "mkcert -version")

        let nginx = FakeNginxLocator()
        nginx.installation = makeNginxInstallation()
        let tooling = LocalServerTooling(shell: shell, nginxLocator: nginx)

        await tooling.refresh()

        #expect(tooling.brew.version == "Homebrew 4.5.0")
        #expect(tooling.mkcert.version == "v1.4.4")
        #expect(tooling.nginx.version == "1.29.4")
        #expect(tooling.brewAvailable)
    }

    @Test
    func reportsMissingTools() async {
        let shell = FakeShellRunner()
        let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())

        await tooling.refresh()

        #expect(tooling.brew == .missing)
        #expect(tooling.mkcert == .missing)
        #expect(tooling.nginx == .missing)
        #expect(!tooling.brewAvailable)
    }

    @Test
    func refreshIsCachedUntilInvalidated() async {
        let shell = FakeShellRunner()
        let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())

        await tooling.refresh()
        let callsAfterFirstRefresh = shell.runCommands.count
        #expect(callsAfterFirstRefresh > 0)

        await tooling.refresh()
        #expect(shell.runCommands.count == callsAfterFirstRefresh)

        tooling.invalidate()
        await tooling.refresh()
        #expect(shell.runCommands.count > callsAfterFirstRefresh)
    }

    @Test
    func statusTracksInstallAndRemoval() async {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "", status: 1), for: "command -v mkcert")
        let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())

        await tooling.refresh(force: true)
        #expect(tooling.mkcert == .missing)

        shell.setResult(ShellResult(output: "/usr/local/bin/mkcert", status: 0), for: "command -v mkcert")
        shell.setResult(ShellResult(output: "v1.4.4", status: 0), for: "mkcert -version")
        await tooling.refresh(force: true)
        #expect(tooling.mkcert.version == "v1.4.4")

        shell.setResult(ShellResult(output: "", status: 1), for: "command -v mkcert")
        await tooling.refresh(force: true)
        #expect(tooling.mkcert == .missing)
    }

    @Test
    func installRequiresHomebrew() async {
        let shell = FakeShellRunner()
        let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())
        await tooling.refresh(force: true)

        do {
            _ = try await tooling.install(.nginx)
            Issue.record("Expected homebrewUnavailable.")
        } catch let error as LocalServerToolingError {
            #expect(error == .homebrewUnavailable)
        } catch {
            Issue.record("Unexpected error \(error).")
        }
    }

    @Test
    func installRunsBrewThenRefreshesStatus() async throws {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.5.0", status: 0), for: "brew --version")
        shell.setResult(ShellResult(output: "installed", status: 0), for: "brew install nginx")

        let nginx = FakeNginxLocator()
        let tooling = LocalServerTooling(shell: shell, nginxLocator: nginx)
        await tooling.refresh(force: true)
        #expect(tooling.nginx == .missing)

        nginx.installation = makeNginxInstallation()
        let status = try await tooling.install(.nginx)

        #expect(shell.runCommands.contains("brew install nginx"))
        #expect(status.version == "1.29.4")
        #expect(tooling.nginx.version == "1.29.4")
    }

    @Test
    func installFailureSurfacesOutput() async {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.5.0", status: 0), for: "brew --version")
        shell.setResult(ShellResult(output: "no network", status: 1), for: "brew install mkcert")

        let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())
        await tooling.refresh(force: true)

        do {
            _ = try await tooling.install(.mkcert)
            Issue.record("Expected installFailed.")
        } catch let error as LocalServerToolingError {
            #expect(error == .installFailed(tool: .mkcert, output: "no network"))
        } catch {
            Issue.record("Unexpected error \(error).")
        }
    }

    @Test
    func homebrewCannotInstallItself() async {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/brew", status: 0), for: "command -v brew")
        shell.setResult(ShellResult(output: "Homebrew 4.5.0", status: 0), for: "brew --version")

        let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())
        await tooling.refresh(force: true)

        do {
            _ = try await tooling.install(.brew)
            Issue.record("Expected notInstallable.")
        } catch let error as LocalServerToolingError {
            #expect(error == .notInstallable(.brew))
        } catch {
            Issue.record("Unexpected error \(error).")
        }
    }
}
