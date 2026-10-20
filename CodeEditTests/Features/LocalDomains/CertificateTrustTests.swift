import Foundation
import Testing
@testable import CodeEdit

@MainActor
struct CertificateTrustTests {
    @Test
    func detectsATrustedAuthority() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let trust = FakeCertificateTrustEvaluator()
            trust.trusted = true
            let authority = makeAuthority(paths: paths, trust: trust)

            let status = await authority.authorityStatus()

            #expect(status == .present(trusted: true))
            #expect(status.isTrusted)
        }
    }

    @Test
    func trustsTheAuthorityThroughTheUserTrustStoreAndVerifies() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let trust = FakeCertificateTrustEvaluator()
            let shell = Self.mkcertShell()
            shell.handler = { command in
                if command.contains("add-trusted-cert") {
                    trust.trusted = true
                    return ShellResult(output: "", status: 0)
                }
                return Self.mkcertResult(command)
            }
            let elevated = FakeElevatedShellRunner()
            let authority = makeAuthority(paths: paths, trust: trust, elevated: elevated, shell: shell)

            try await authority.trustAuthority()

            #expect(elevated.commands.isEmpty)
            #expect(shell.runCommands.contains { $0.contains("add-trusted-cert -r trustRoot") })
            #expect(authority.status == .present(trusted: true))
        }
    }

    @Test
    func createsTheAuthorityAsTheUserBeforeTrusting() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try FileManager.default.createDirectory(at: paths.certificates, withIntermediateDirectories: true)
            let trust = FakeCertificateTrustEvaluator()
            let shell = Self.mkcertShell()
            shell.handler = { command in
                if command.contains("-cert-file") {
                    let manager = FileManager.default
                    try? manager.createDirectory(at: paths.root, withIntermediateDirectories: true)
                    try? Data("authority".utf8).write(to: paths.rootCertificate)
                    try? Data("authority-key".utf8).write(to: paths.rootKey)
                    return ShellResult(output: "", status: 0)
                }
                if command.contains("add-trusted-cert") {
                    trust.trusted = true
                    return ShellResult(output: "", status: 0)
                }
                return Self.mkcertResult(command)
            }
            let elevated = FakeElevatedShellRunner()
            let authority = makeAuthority(paths: paths, trust: trust, elevated: elevated, shell: shell)

            try await authority.trustAuthority()

            #expect(shell.runCommands.contains { $0.contains("-cert-file") })
            #expect(elevated.commands.isEmpty)
            #expect(trust.queriedURLs.contains(paths.rootCertificate))
        }
    }

    @Test
    func reportsCancelledTrustAndKeepsHttpAvailable() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let shell = Self.mkcertShell()
            shell.setResult(
                ShellResult(output: "execution error: User canceled. (-128)", status: 1),
                for: Self.trustCommand(for: paths)
            )
            let elevated = FakeElevatedShellRunner()
            let authority = makeAuthority(
                paths: paths,
                trust: FakeCertificateTrustEvaluator(),
                elevated: elevated,
                shell: shell
            )

            await #expect(throws: CertificateAuthorityError.trustCancelled) {
                try await authority.trustAuthority()
            }

            let error = CertificateAuthorityError.trustCancelled
            #expect(error.recoverySuggestion?.contains("HTTP") == true)
            let status = await authority.authorityStatus()
            #expect(status == .present(trusted: false))
        }
    }

    @Test
    func reportsTrustFailureWhenVerificationFails() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let shell = Self.mkcertShell()
            shell.setResult(ShellResult(output: "", status: 0), for: Self.trustCommand(for: paths))
            let elevated = FakeElevatedShellRunner()
            let authority = makeAuthority(
                paths: paths,
                trust: FakeCertificateTrustEvaluator(),
                elevated: elevated,
                shell: shell
            )

            await #expect(throws: CertificateAuthorityError.trustFailed(
                "The authority is not trusted after installing it."
            )) {
                try await authority.trustAuthority()
            }
        }
    }

    @Test
    func reportsWhenMkcertIsMissingWhileTrusting() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let shell = FakeShellRunner()
            let authority = makeAuthority(
                paths: paths,
                trust: FakeCertificateTrustEvaluator(),
                elevated: FakeElevatedShellRunner(),
                shell: shell
            )

            await #expect(throws: CertificateAuthorityError.mkcertUnavailable) {
                try await authority.trustAuthority()
            }
        }
    }

    @Test
    func resetRemovesUserTrustWithoutElevation() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let trust = FakeCertificateTrustEvaluator()
            trust.trusted = true
            let shell = Self.mkcertShell()
            shell.setResult(
                ShellResult(output: "", status: 0),
                for: "/usr/bin/security remove-trusted-cert '\(paths.rootCertificate.path(percentEncoded: false))'"
            )
            let elevated = FakeElevatedShellRunner()
            let authority = makeAuthority(
                paths: paths,
                trust: trust,
                elevated: elevated,
                shell: shell
            )

            try await authority.resetAuthority()

            #expect(elevated.commands.isEmpty)
            #expect(shell.runCommands.contains { $0.contains("remove-trusted-cert") })
            #expect(authority.status == .missing)
            #expect(!FileManager.default.fileExists(atPath: paths.rootCertificate.path(percentEncoded: false)))
        }
    }

    @Test
    func resetFallsBackToTheAdminTrustStore() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let trust = FakeCertificateTrustEvaluator()
            trust.trusted = true
            let elevated = FakeElevatedShellRunner()
            let authority = makeAuthority(paths: paths, trust: trust, elevated: elevated)

            try await authority.resetAuthority()

            #expect(elevated.commands.first?.contains("remove-trusted-cert -d") == true)
            #expect(authority.status == .missing)
            #expect(!FileManager.default.fileExists(atPath: paths.rootCertificate.path(percentEncoded: false)))
        }
    }

    @Test
    func resetSkipsElevationWhenTheAuthorityIsUntrusted() async throws {
        try await withTempDir { directory in
            let paths = paths(in: directory)
            try writeAuthorityFiles(at: paths)
            let elevated = FakeElevatedShellRunner()
            let authority = makeAuthority(
                paths: paths,
                trust: FakeCertificateTrustEvaluator(),
                elevated: elevated
            )

            try await authority.resetAuthority()

            #expect(elevated.commands.isEmpty)
            #expect(authority.status == .missing)
        }
    }

    @Test
    func appleScriptLiteralEscapesQuotesAndBackslashes() {
        let literal = AppleScriptElevatedShellRunner.appleScriptLiteral(#"a"b\c"#)
        #expect(literal == #""a\"b\\c""#)
    }

    // MARK: - Helpers

    private func paths(in directory: URL) -> CertificateAuthorityPaths {
        CertificateAuthorityPaths(
            root: directory.appending(path: "ca", directoryHint: .isDirectory),
            certificates: directory.appending(path: "certs", directoryHint: .isDirectory)
        )
    }

    private func writeAuthorityFiles(at paths: CertificateAuthorityPaths) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try manager.createDirectory(at: paths.certificates, withIntermediateDirectories: true)
        try Data("authority".utf8).write(to: paths.rootCertificate)
        try Data("authority-key".utf8).write(to: paths.rootKey)
    }

    private func makeAuthority(
        paths: CertificateAuthorityPaths,
        trust: FakeCertificateTrustEvaluator,
        elevated: FakeElevatedShellRunner? = nil,
        shell: FakeShellRunner? = nil
    ) -> CertificateAuthority {
        let runner = shell ?? Self.mkcertShell()
        return CertificateAuthority(
            tooling: LocalServerTooling(shell: runner, nginxLocator: FakeNginxLocator()),
            shell: runner,
            inspector: FakeCertificateInspector(),
            trustEvaluator: trust,
            elevatedShell: elevated ?? FakeElevatedShellRunner(),
            paths: paths
        )
    }

    private static func mkcertShell() -> FakeShellRunner {
        let shell = FakeShellRunner()
        shell.setResult(ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0), for: "command -v mkcert")
        shell.setResult(ShellResult(output: "v1.4.4", status: 0), for: "mkcert -version")
        shell.setResult(
            ShellResult(output: "\"\(testKeychain)\"", status: 0),
            for: "/usr/bin/security default-keychain -d user"
        )
        return shell
    }

    nonisolated private static func mkcertResult(_ command: String) -> ShellResult {
        switch command {
        case "command -v mkcert":
            return ShellResult(output: "/opt/homebrew/bin/mkcert", status: 0)
        case "mkcert -version":
            return ShellResult(output: "v1.4.4", status: 0)
        case "/usr/bin/security default-keychain -d user":
            return ShellResult(output: "\"\(testKeychain)\"", status: 0)
        default:
            return ShellResult(output: "", status: 1)
        }
    }

    private static let testKeychain = "/Users/test/Library/Keychains/login.keychain-db"

    private static func trustCommand(for paths: CertificateAuthorityPaths) -> String {
        "/usr/bin/security add-trusted-cert -r trustRoot -k '\(testKeychain)' "
            + "'\(paths.rootCertificate.path(percentEncoded: false))'"
    }
}
