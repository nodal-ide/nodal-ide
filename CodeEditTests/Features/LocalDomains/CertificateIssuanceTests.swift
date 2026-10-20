import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct CertificateIssuanceTests {
    @Test
    func issuesAndCachesACertificate() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            let shell = Self.mkcertShell()
            let authority = makeAuthority(shell: shell, inspector: inspector(), paths: paths)
            let domain = try SiteDomain("app.localhost")

            let first = try await authority.certificate(for: domain)
            let second = try await authority.certificate(for: domain)

            #expect(first.certificateURL == paths.certificate(for: "app.localhost"))
            #expect(first.privateKeyURL == paths.privateKey(for: "app.localhost"))
            #expect(first.expiresAt == Self.expiry)
            #expect(second.certificateURL == first.certificateURL)
            #expect(Self.mkcertInvocations(shell) == 1)

            let keyPermissions = try Self.permissions(of: paths.privateKey(for: "app.localhost"))
            let metadataExists = FileManager.default.fileExists(
                atPath: paths.metadata(for: "app.localhost").path(percentEncoded: false)
            )
            #expect(keyPermissions == 0o600)
            #expect(metadataExists)
        }
    }

    @Test
    func reissuesAnExpiredCertificate() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            let shell = Self.mkcertShell()
            let expired = FakeCertificateInspector()
            expired.setResult(CertificateDetails(notAfter: Date(timeIntervalSince1970: 100), domains: []))
            let authority = makeAuthority(
                shell: shell,
                inspector: expired,
                paths: paths
            )
            let domain = try SiteDomain("app.localhost")

            _ = try await authority.certificate(for: domain)
            _ = try await authority.certificate(for: domain)

            #expect(Self.mkcertInvocations(shell) == 2)
        }
    }

    @Test
    func reissuesWhenTheAuthorityChanges() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            let shell = Self.mkcertShell()
            let authority = makeAuthority(shell: shell, inspector: inspector(), paths: paths)
            let domain = try SiteDomain("app.localhost")

            _ = try await authority.certificate(for: domain)
            try Data("rotated-authority".utf8).write(to: paths.rootCertificate)
            _ = try await authority.certificate(for: domain)

            #expect(Self.mkcertInvocations(shell) == 2)
        }
    }

    @Test
    func reportsWhenMkcertIsUnavailable() async throws {
        try await withTempDir { directory in
            let shell = FakeShellRunner()
            let authority = makeAuthority(shell: shell, inspector: inspector(), paths: paths(in: directory))

            await #expect(throws: CertificateAuthorityError.mkcertUnavailable) {
                _ = try await authority.certificate(for: SiteDomain("app.localhost"))
            }
        }
    }

    @Test
    func reportsIssuanceFailure() async throws {
        try await withTempDir { directory in
            let shell = Self.mkcertShell(failIssuance: true)
            let authority = makeAuthority(shell: shell, inspector: inspector(), paths: paths(in: directory))

            await #expect(throws: CertificateAuthorityError.issuanceFailed("boom")) {
                _ = try await authority.certificate(for: SiteDomain("app.localhost"))
            }
        }
    }

    @Test
    func reissuesWhenTheDomainIsNotInTheCachedSans() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            let shell = Self.mkcertShell()
            let sansInspector = FakeCertificateInspector()
            sansInspector.setResult(CertificateDetails(notAfter: Self.expiry, domains: ["other.localhost"]))
            let authority = makeAuthority(shell: shell, inspector: sansInspector, paths: paths)
            let domain = try SiteDomain("app.localhost")

            _ = try await authority.certificate(for: domain)
            sansInspector.setResult(CertificateDetails(notAfter: Self.expiry, domains: ["app.localhost"]))
            _ = try await authority.certificate(for: domain)

            #expect(Self.mkcertInvocations(shell) == 2)
        }
    }

    // MARK: - Helpers

    private static let expiry = Date(timeIntervalSince1970: 10_000_000)

    private func paths(in directory: URL) -> CertificateAuthorityPaths {
        CertificateAuthorityPaths(
            root: directory.appending(path: "ca", directoryHint: .isDirectory),
            certificates: directory.appending(path: "certs", directoryHint: .isDirectory)
        )
    }

    private func inspector() -> FakeCertificateInspector {
        let inspector = FakeCertificateInspector()
        inspector.setResult(CertificateDetails(notAfter: Self.expiry, domains: ["app.localhost"]))
        return inspector
    }

    private func makeAuthority(
        shell: FakeShellRunner,
        inspector: FakeCertificateInspector,
        paths: CertificateAuthorityPaths
    ) -> CertificateAuthority {
        CertificateAuthority(
            tooling: LocalServerTooling(shell: shell, nginxLocator: FakeNginxLocator()),
            shell: shell,
            inspector: inspector,
            timeSource: FakeTimeSource(now: Date(timeIntervalSince1970: 0)),
            paths: paths
        )
    }

    private static func mkcertShell(failIssuance: Bool = false) -> FakeShellRunner {
        let shell = FakeShellRunner()
        shell.handler = { command in issuanceHandler(command, failIssuance: failIssuance) }
        return shell
    }

    private static func mkcertInvocations(_ shell: FakeShellRunner) -> Int {
        shell.runCommands.filter { $0.contains("-cert-file") }.count
    }

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    private nonisolated static func issuanceHandler(_ command: String, failIssuance: Bool) -> ShellResult {
        switch command {
        case "command -v mkcert":
            return ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0)
        case "mkcert -version":
            return ShellResult(output: "v1.4.4", status: 0)
        default:
            break
        }

        guard command.contains("-cert-file") else {
            return ShellResult(output: "", status: 1)
        }
        guard !failIssuance else {
            return ShellResult(output: "boom", status: 1)
        }

        guard let caroot = quotedValue(after: "CAROOT=", in: command),
              let certificate = quotedValue(after: "-cert-file ", in: command),
              let key = quotedValue(after: "-key-file ", in: command) else {
            return ShellResult(output: "could not parse command", status: 1)
        }

        let manager = FileManager.default
        manager.createFile(atPath: caroot + "/rootCA.pem", contents: Data("authority".utf8))
        manager.createFile(atPath: caroot + "/rootCA-key.pem", contents: Data("authority-key".utf8))
        manager.createFile(atPath: certificate, contents: Data("certificate".utf8))
        manager.createFile(atPath: key, contents: Data("key".utf8))
        return ShellResult(output: "created", status: 0)
    }

    /// Extracts the single-quoted value following `prefix`.
    private nonisolated static func quotedValue(after prefix: String, in command: String) -> String? {
        guard let range = command.range(of: prefix) else {
            return nil
        }
        let remainder = command[range.upperBound...]
        guard remainder.first == "'" else {
            return nil
        }
        let body = remainder.dropFirst()
        guard let end = body.firstIndex(of: "'") else {
            return nil
        }
        return String(body[body.startIndex..<end])
    }
}
