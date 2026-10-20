import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct CertificateAuthorityTests {
    @Test
    func detectsAMissingAuthorityAndCreatesLockedDownDirectories() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            let authority = CertificateAuthority(shell: FakeShellRunner(), paths: paths)

            let status = await authority.authorityStatus()
            let rootPermissions = try Self.permissions(of: paths.root)
            let certificatePermissions = try Self.permissions(of: paths.certificates)

            #expect(status == .missing)
            #expect(rootPermissions == 0o700)
            #expect(certificatePermissions == 0o700)
        }
    }

    @Test
    func detectsAnExistingAuthority() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            try Data("certificate".utf8).write(to: paths.rootCertificate)
            try Data("key".utf8).write(to: paths.rootKey)

            let authority = CertificateAuthority(shell: FakeShellRunner(), paths: paths)
            let status = await authority.authorityStatus()

            #expect(status == .present(trusted: false))
            #expect(!status.isTrusted)
        }
    }

    @Test
    func installsMkcertThroughHomebrew() async throws {
        try await withTempDir { directory in
            let state = MkcertInstallState()
            let shell = FakeShellRunner()
            shell.handler = { command in Self.installHandler(command, state: state) }
            let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())
            let authority = CertificateAuthority(tooling: tooling, shell: shell, paths: paths(in: directory))

            try await authority.installMkcert()

            #expect(authority.mkcertStatus.isInstalled)
            #expect(shell.runCommands.contains("brew install mkcert"))
        }
    }

    @Test
    func reportsWhenMkcertCannotBeInstalled() async throws {
        try await withTempDir { directory in
            let shell = FakeShellRunner()
            let tooling = LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator())
            let authority = CertificateAuthority(tooling: tooling, shell: shell, paths: paths(in: directory))

            do {
                try await authority.installMkcert()
                Issue.record("Expected installMkcert to throw when Homebrew is unavailable.")
            } catch is CertificateAuthorityError {
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func paths(in directory: URL) -> CertificateAuthorityPaths {
        CertificateAuthorityPaths(
            root: directory.appending(path: "ca", directoryHint: .isDirectory),
            certificates: directory.appending(path: "certs", directoryHint: .isDirectory)
        )
    }

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    private nonisolated static func installHandler(_ command: String, state: MkcertInstallState) -> ShellResult {
        switch command {
        case "command -v brew":
            return ShellResult(output: "/opt/homebrew/bin/brew", status: 0)
        case "brew --version":
            return ShellResult(output: "Homebrew 4.0.0", status: 0)
        case "brew install mkcert":
            state.markInstalled()
            return ShellResult(output: "installed", status: 0)
        case "command -v mkcert":
            return state.isInstalled
                ? ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0)
                : ShellResult(output: "", status: 1)
        case "mkcert -version":
            return ShellResult(output: "v1.4.4", status: 0)
        default:
            return ShellResult(output: "", status: 1)
        }
    }
}

private final class MkcertInstallState: @unchecked Sendable {
    private let lock = NSLock()
    private var installed = false

    func markInstalled() {
        lock.lock()
        installed = true
        lock.unlock()
    }

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return installed
    }
}
