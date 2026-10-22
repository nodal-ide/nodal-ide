import Foundation

/// A redacted, copyable snapshot of the local-domain environment. Rendering is pure so the format is
/// testable without touching the filesystem or tools.
struct ProxyDiagnosticsReport: Equatable, Sendable {
    let generatedAt: Date
    let appVersion: String
    let macOSVersion: String
    let proxyRoot: String
    let portMode: String
    let tools: [String]
    let authority: String
    let siteDomains: [String]
    let recentErrors: [String]
    let lastError: String?

    func rendered() -> String {
        var lines = [
            "Nodal IDE Local Domains Diagnostics",
            "Generated: \(ISO8601DateFormatter().string(from: generatedAt))",
            "Nodal IDE: \(appVersion)",
            "macOS: \(macOSVersion)",
            "Proxy root: \(proxyRoot)",
            "Port mode: \(portMode)"
        ]
        lines.append(contentsOf: tools)
        lines.append("Certificate authority: \(authority)")

        if siteDomains.isEmpty {
            lines.append("Registered sites: none")
        } else {
            lines.append("Registered sites: \(siteDomains.count)")
            lines.append(contentsOf: siteDomains.map { "  - \($0)" })
        }

        lines.append("Recent nginx errors:")
        if recentErrors.isEmpty {
            lines.append("  (none)")
        } else {
            lines.append(contentsOf: recentErrors.map { "  \($0)" })
        }

        if let lastError {
            lines.append("Last action error: \(lastError)")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class LocalDomainsDiagnostics {
    private let prefix: NginxPrefix
    private let authorityPaths: CertificateAuthorityPaths
    private let tooling: LocalServerTooling
    private let authority: any CertificateProviding
    private let registry: SiteRegistry
    private let homeDirectory: URL
    private let timeSource: any TimeSource
    private let fileManager: FileManager
    private let appVersion: () -> String
    private let macOSVersion: () -> String
    private let stopper: any ProxyProcessStopping

    init(
        prefix: NginxPrefix = .default,
        authorityPaths: CertificateAuthorityPaths = .default,
        tooling: LocalServerTooling,
        authority: any CertificateProviding,
        registry: SiteRegistry? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeSource: any TimeSource = SystemTimeSource(),
        fileManager: FileManager = .default,
        appVersion: @escaping () -> String = {
            let version = Bundle.versionString ?? "unknown"
            let build = Bundle.buildString ?? "unknown"
            return "\(version) (\(build))"
        },
        macOSVersion: @escaping () -> String = {
            ProcessInfo.processInfo.operatingSystemVersionString
        },
        stopper: (any ProxyProcessStopping)? = nil
    ) {
        self.prefix = prefix
        self.authorityPaths = authorityPaths
        self.tooling = tooling
        self.authority = authority
        self.registry = registry ?? AppServices.localProxy.registry
        self.homeDirectory = homeDirectory
        self.timeSource = timeSource
        self.fileManager = fileManager
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.stopper = stopper ?? NginxPidFileStopper()
    }

    func report(
        portMode: SettingsData.LocalDomainsSettings.PortMode,
        lastError: String? = nil
    ) async -> String {
        await tooling.refresh()
        let authorityStatus = await authority.authorityStatus()
        let tools = [
            Self.toolLine("Homebrew", status: tooling.brew, home: homeDirectory),
            Self.toolLine("nginx", status: tooling.nginx, home: homeDirectory),
            Self.toolLine("mkcert", status: tooling.mkcert, home: homeDirectory)
        ]
        let siteDomains = registry.registrations.map(\.domain.value).sorted()
        let recentErrors = ((try? LogFileTail.lines(
            at: prefix.errorLogURL,
            maxLines: 20,
            maxBytes: 16 * 1024
        )) ?? []).map { Self.redact($0, home: homeDirectory) }

        let report = ProxyDiagnosticsReport(
            generatedAt: timeSource.now,
            appVersion: appVersion(),
            macOSVersion: macOSVersion(),
            proxyRoot: Self.redact(
                prefix.root.deletingLastPathComponent().path(percentEncoded: false),
                home: homeDirectory
            ),
            portMode: portMode.title,
            tools: tools,
            authority: Self.describe(authorityStatus),
            siteDomains: siteDomains,
            recentErrors: recentErrors,
            lastError: lastError.map { Self.redact($0, home: homeDirectory) }
        )
        return report.rendered()
    }

    /// Stops a stale nginx master, then removes generated configs, logs, temp files, and certificates.
    /// The certificate authority itself (and the cross-process lock) are kept.
    func resetGeneratedState() async throws {
        try await stopper.stopIfRunning(pidURL: prefix.pidURL)

        let paths = [
            prefix.generationsDirectory,
            prefix.currentSymlink,
            prefix.logsDirectory,
            prefix.tempDirectory,
            prefix.runDirectory,
            prefix.mimeTypesURL,
            authorityPaths.certificates
        ]
        for url in paths {
            let path = url.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: path) else {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw ProxyStateResetError.removalFailed(path: path, message: error.localizedDescription)
            }
        }

        do {
            try prefix.createDirectories()
        } catch {
            throw ProxyStateResetError.removalFailed(
                path: prefix.root.path(percentEncoded: false),
                message: error.localizedDescription
            )
        }
    }

    private static func toolLine(
        _ name: String,
        status: LocalServerToolStatus,
        home: URL
    ) -> String {
        switch status {
        case .unknown:
            return "\(name): checking"
        case .missing:
            return "\(name): not installed"
        case .installed(let installation):
            let version = installation.version.isEmpty ? "unknown version" : installation.version
            let path = redact(installation.executableURL.path(percentEncoded: false), home: home)
            return "\(name): \(version) (\(path))"
        }
    }

    private static func describe(_ status: CertificateAuthorityStatus) -> String {
        switch status {
        case .missing: return "not created"
        case .present(trusted: true): return "trusted"
        case .present(trusted: false): return "not trusted"
        }
    }

    static func redact(_ text: String, home: URL) -> String {
        var result = text
        var homePath = home.path(percentEncoded: false)
        while homePath.count > 1 && homePath.hasSuffix("/") {
            homePath.removeLast()
        }
        if homePath.count > 1 {
            result = result.replacingOccurrences(of: homePath, with: "~")
        }
        result = result.replacingOccurrences(
            of: #"\?[^\s"]+"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)(password|passwd|token|secret|api[_-]?key)=([^&\s]+)"#,
            with: "$1=<redacted>",
            options: .regularExpression
        )
        return result
    }
}
