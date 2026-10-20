import CryptoKit
import Foundation

/// App-owned certificate authority: an mkcert `CAROOT` kept under `~/.codeedit/proxy/ca` (`0700`),
/// with detection of mkcert and the CA files, plus cached leaf certificate issuance.
@MainActor
final class CertificateAuthority: CertificateProviding {
    let paths: CertificateAuthorityPaths

    private let tooling: LocalServerTooling
    private let shell: any ShellRunning
    private let inspector: any CertificateInspecting
    private let trustEvaluator: any CertificateTrustEvaluating
    private let elevatedShell: any ElevatedShellRunning
    private let timeSource: any TimeSource
    private let fileManager: FileManager
    private let renewalMargin: TimeInterval

    private(set) var status: CertificateAuthorityStatus = .missing

    init(
        tooling: LocalServerTooling? = nil,
        shell: any ShellRunning = SystemShellRunner(),
        inspector: any CertificateInspecting = SecurityCertificateInspector(),
        trustEvaluator: (any CertificateTrustEvaluating)? = nil,
        elevatedShell: (any ElevatedShellRunning)? = nil,
        timeSource: any TimeSource = SystemTimeSource(),
        paths: CertificateAuthorityPaths = .default,
        fileManager: FileManager = .default,
        renewalMargin: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.tooling = tooling ?? LocalServerTooling(shell: shell, nginxLocator: SystemNginxLocator(shell: shell))
        self.shell = shell
        self.inspector = inspector
        self.trustEvaluator = trustEvaluator ?? SecurityCertificateTrustEvaluator()
        self.elevatedShell = elevatedShell ?? AppleScriptElevatedShellRunner()
        self.timeSource = timeSource
        self.paths = paths
        self.fileManager = fileManager
        self.renewalMargin = renewalMargin
    }

    var mkcertStatus: LocalServerToolStatus {
        tooling.mkcert
    }

    /// `CAROOT` value to pass to mkcert so it never touches the user's own CA.
    var caroot: String {
        paths.root.path(percentEncoded: false)
    }

    var hasAuthorityFiles: Bool {
        fileManager.fileExists(atPath: paths.rootCertificate.path(percentEncoded: false))
            && fileManager.fileExists(atPath: paths.rootKey.path(percentEncoded: false))
    }

    /// Creates the app-owned CA/certificate directories with `0700` permissions.
    func createDirectories() throws {
        for directory in [paths.root, paths.certificates] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    /// Re-probes mkcert and the CA files, and checks whether the CA is trusted by the system.
    func refresh() async {
        try? createDirectories()
        await tooling.refresh()
        status = hasAuthorityFiles
            ? .present(trusted: trustEvaluator.isTrusted(certificateAt: paths.rootCertificate))
            : .missing
    }

    /// Installs mkcert through Homebrew (creating the CA is a separate, explicit step).
    func installMkcert() async throws {
        await tooling.refresh()
        do {
            let installed = try await tooling.install(.mkcert)
            guard installed.isInstalled else {
                throw CertificateAuthorityError.mkcertUnavailable
            }
        } catch let error as LocalServerToolingError {
            throw CertificateAuthorityError.installFailed(error.localizedDescription)
        }
        await refresh()
    }

    /// SHA-256 of the CA certificate, used to detect a regenerated/rotated authority.
    func authorityFingerprint() throws -> String? {
        guard fileManager.fileExists(atPath: paths.rootCertificate.path(percentEncoded: false)) else {
            return nil
        }
        let data = try Data(contentsOf: paths.rootCertificate)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - CertificateProviding

    func authorityStatus() async -> CertificateAuthorityStatus {
        await refresh()
        return status
    }

    /// Returns a cached leaf certificate when it is still valid and was issued by the current CA,
    /// otherwise issues a fresh one through mkcert using the app-local `CAROOT`.
    func certificate(for domain: SiteDomain) async throws -> SiteCertificate {
        try createDirectories()
        let domainValue = domain.value
        let certificateURL = paths.certificate(for: domainValue)
        let keyURL = paths.privateKey(for: domainValue)

        if let cached = try reusableCertificate(domain: domain, certificateURL: certificateURL, keyURL: keyURL) {
            return cached
        }

        try await issue(
            domain: domain,
            certificateURL: certificateURL,
            keyURL: keyURL,
            metadataURL: paths.metadata(for: domainValue)
        )

        let details = try inspector.details(forCertificateAt: certificateURL)
        return SiteCertificate(
            domain: domain,
            certificateURL: certificateURL,
            privateKeyURL: keyURL,
            expiresAt: details.notAfter
        )
    }

    // MARK: - Caching

    private func reusableCertificate(
        domain: SiteDomain,
        certificateURL: URL,
        keyURL: URL
    ) throws -> SiteCertificate? {
        let metadataURL = paths.metadata(for: domain.value)
        guard fileManager.fileExists(atPath: certificateURL.path(percentEncoded: false)),
              fileManager.fileExists(atPath: keyURL.path(percentEncoded: false)),
              let metadata = try? Self.readMetadata(at: metadataURL) else {
            return nil
        }
        guard metadata.domains.contains(domain.value) else {
            return nil
        }
        guard metadata.notAfter > timeSource.now.addingTimeInterval(renewalMargin) else {
            return nil
        }
        guard let fingerprint = try authorityFingerprint(), fingerprint == metadata.authorityFingerprint else {
            return nil
        }
        return SiteCertificate(
            domain: domain,
            certificateURL: certificateURL,
            privateKeyURL: keyURL,
            expiresAt: metadata.notAfter
        )
    }

    // MARK: - Issuance

    private func issue(
        domain: SiteDomain,
        certificateURL: URL,
        keyURL: URL,
        metadataURL: URL
    ) async throws {
        await tooling.refresh()
        let executable = try mkcertExecutable()

        let token = UUID().uuidString
        let temporaryCertificate = paths.certificates.appending(path: ".\(domain.value)-\(token).pem")
        let temporaryKey = paths.certificates.appending(path: ".\(domain.value)-\(token)-key.pem")
        defer {
            try? fileManager.removeItem(at: temporaryCertificate)
            try? fileManager.removeItem(at: temporaryKey)
        }

        let command = [
            "CAROOT=\(Self.quote(caroot))",
            Self.quote(executable),
            "-cert-file", Self.quote(temporaryCertificate.path(percentEncoded: false)),
            "-key-file", Self.quote(temporaryKey.path(percentEncoded: false)),
            Self.quote(domain.value)
        ].joined(separator: " ")

        let result = await shell.run(command)
        guard result.succeeded else {
            throw CertificateAuthorityError.issuanceFailed(result.output)
        }

        guard let details = try? inspector.details(forCertificateAt: temporaryCertificate) else {
            throw CertificateAuthorityError.inspectionFailed(Self.lastLine(of: result.output))
        }
        guard let fingerprint = try authorityFingerprint() else {
            throw CertificateAuthorityError.inspectionFailed("The certificate authority was not created.")
        }

        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temporaryKey.path(percentEncoded: false)
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: temporaryCertificate.path(percentEncoded: false)
        )

        let metadata = SiteCertificateMetadata(
            domains: details.domains.isEmpty ? [domain.value] : details.domains,
            notAfter: details.notAfter,
            authorityFingerprint: fingerprint
        )
        let encoded = try Self.encoder.encode(metadata)

        try Self.replaceItem(at: certificateURL, with: temporaryCertificate, fileManager: fileManager)
        try Self.replaceItem(at: keyURL, with: temporaryKey, fileManager: fileManager)
        try encoded.write(to: metadataURL, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: metadataURL.path(percentEncoded: false)
        )
    }

    private func mkcertExecutable() throws -> String {
        switch tooling.mkcert {
        case .installed(let installation):
            return installation.executableURL.path(percentEncoded: false)
        case .unknown, .missing:
            throw CertificateAuthorityError.mkcertUnavailable
        }
    }

    private func removeCertificates() throws {
        guard fileManager.fileExists(atPath: paths.certificates.path(percentEncoded: false)) else {
            return
        }
        for entry in try fileManager.contentsOfDirectory(at: paths.certificates, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: entry)
        }
    }
}

// MARK: - Trust

extension CertificateAuthority {
    /// Creates the app-owned CA as the current user and adds it to the user's trust settings.
    ///
    /// macOS 11+ rejects admin trust changes made by a process that merely runs as root, so the trust
    /// command must run unelevated and let SecurityAgent ask the user directly. The CA is created
    /// before trusting it so mkcert never generates a root-owned key inside an elevated process.
    ///
    /// A declined prompt surfaces as ``CertificateAuthorityError/trustCancelled`` so callers can keep
    /// serving over HTTP. After the prompt, trust is verified with `SecTrust` rather than assumed.
    func trustAuthority() async throws {
        try createDirectories()
        await tooling.refresh()
        let executable = try mkcertExecutable()
        try await ensureAuthorityExists(executable: executable)

        let certificate = paths.rootCertificate.path(percentEncoded: false)
        let keychain = await userKeychain()
        let destination = keychain.map { " -k \(Self.quote($0))" } ?? ""
        let command = "/usr/bin/security add-trusted-cert -r trustRoot\(destination) "
            + Self.quote(certificate)
        let result = await shell.run(command)
        if Self.isCancellation(result) {
            throw CertificateAuthorityError.trustCancelled
        }
        guard result.succeeded else {
            throw CertificateAuthorityError.trustFailed(Self.diagnosticOutput(of: result.output))
        }
        guard trustEvaluator.isTrusted(certificateAt: paths.rootCertificate) else {
            throw CertificateAuthorityError.trustFailed("The authority is not trusted after installing it.")
        }
        await refresh()
    }

    /// Removes the CA from the user's trust store (falling back to the admin store for authorities
    /// trusted by older versions) and deletes the app-owned CA and leaf certificates.
    func resetAuthority() async throws {
        if hasAuthorityFiles, trustEvaluator.isTrusted(certificateAt: paths.rootCertificate) {
            let certificate = paths.rootCertificate.path(percentEncoded: false)
            let removeCommand = "/usr/bin/security remove-trusted-cert \(Self.quote(certificate))"
            let result = await shell.run(removeCommand)
            if Self.isCancellation(result) {
                throw CertificateAuthorityError.trustCancelled
            }
            if !result.succeeded, trustEvaluator.isTrusted(certificateAt: paths.rootCertificate) {
                let adminCommand = "/usr/bin/security remove-trusted-cert -d \(Self.quote(certificate))"
                let adminResult = await elevatedShell.run(adminCommand)
                if Self.isCancellation(adminResult) {
                    throw CertificateAuthorityError.trustCancelled
                }
                guard adminResult.succeeded else {
                    throw CertificateAuthorityError.resetFailed(
                        Self.diagnosticOutput(of: adminResult.output)
                    )
                }
            }
        }

        try? removeCertificates()
        try? fileManager.removeItem(at: paths.root)
        status = .missing
    }

    private func userKeychain() async -> String? {
        let result = await shell.run("/usr/bin/security default-keychain -d user")
        guard result.succeeded else {
            return nil
        }
        let path = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return path.isEmpty ? nil : path
    }

    /// mkcert creates the CA on demand, but an elevated `-install` would create it as root. Bootstrap it
    /// from the user's account (and replace a root-owned key left by an earlier failed attempt).
    private func ensureAuthorityExists(executable: String) async throws {
        if hasAuthorityFiles, fileManager.isReadableFile(atPath: paths.rootKey.path(percentEncoded: false)) {
            return
        }
        if hasAuthorityFiles {
            try? fileManager.removeItem(at: paths.rootCertificate)
            try? fileManager.removeItem(at: paths.rootKey)
            try? removeCertificates()
        }

        let token = UUID().uuidString
        let certificate = paths.certificates.appending(path: ".ca-bootstrap-\(token).pem")
        let key = paths.certificates.appending(path: ".ca-bootstrap-\(token)-key.pem")
        defer {
            try? fileManager.removeItem(at: certificate)
            try? fileManager.removeItem(at: key)
        }

        let command = [
            "CAROOT=\(Self.quote(caroot))",
            Self.quote(executable),
            "-cert-file", Self.quote(certificate.path(percentEncoded: false)),
            "-key-file", Self.quote(key.path(percentEncoded: false)),
            "localhost"
        ].joined(separator: " ")
        let result = await shell.run(command)
        guard result.succeeded,
              hasAuthorityFiles,
              fileManager.isReadableFile(atPath: paths.rootKey.path(percentEncoded: false)) else {
            throw CertificateAuthorityError.issuanceFailed(Self.diagnosticOutput(of: result.output))
        }
    }
}
