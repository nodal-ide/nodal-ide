import Foundation
@testable import CodeEdit

@MainActor
final class FakePHPFPMDetector: PHPFPMDetecting {
    var statuses: [String: PHPFPMStatus] = [:]
    var defaultStatus: PHPFPMStatus = .missing
    private(set) var probedRuntimes: [InstalledRuntime] = []

    func status(for runtime: InstalledRuntime) async -> PHPFPMStatus {
        probedRuntimes.append(runtime)
        return statuses[runtime.id] ?? defaultStatus
    }
}

@MainActor
final class FakeCertificateProvider: CertificateProviding {
    var status: CertificateAuthorityStatus = .missing
    var certificateResult: Result<SiteCertificate, Error>?
    var trustResult: Result<Void, Error>?
    var resetResult: Result<Void, Error>?
    private(set) var trustCalls = 0
    private(set) var resetCalls = 0

    func authorityStatus() async -> CertificateAuthorityStatus {
        status
    }

    func certificate(for domain: SiteDomain) async throws -> SiteCertificate {
        if let certificateResult {
            return try certificateResult.get()
        }
        return SiteCertificate(
            domain: domain,
            certificateURL: URL(filePath: "/tmp/\(domain.value).pem"),
            privateKeyURL: URL(filePath: "/tmp/\(domain.value)-key.pem"),
            expiresAt: .distantFuture
        )
    }

    func trustAuthority() async throws {
        trustCalls += 1
        if let trustResult {
            try trustResult.get()
            return
        }
        status = .present(trusted: true)
    }

    func resetAuthority() async throws {
        resetCalls += 1
        if let resetResult {
            try resetResult.get()
            return
        }
        status = .missing
    }
}

@MainActor
final class FakeNginxLocator: NginxLocating {
    var installation: NginxInstallation?
    var inspectedInstallations: [URL: NginxInstallation] = [:]
    private(set) var locateCalls = 0

    func locate() async -> NginxInstallation? {
        locateCalls += 1
        return installation
    }

    func inspect(_ executableURL: URL) async -> NginxInstallation? {
        inspectedInstallations[executableURL]
    }
}

final class FakeShellRunner: ShellRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [String: ShellResult] = [:]
    private var defaultResult = ShellResult(output: "", status: 1)
    private var commands: [String] = []

    /// When set, decides the result for every command (overrides `results`/`defaultResult`).
    var handler: (@Sendable (String) -> ShellResult)?

    var runCommands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return commands
    }

    func setResult(_ result: ShellResult, for command: String) {
        lock.lock()
        results[command] = result
        lock.unlock()
    }

    func setDefault(_ result: ShellResult) {
        lock.lock()
        defaultResult = result
        lock.unlock()
    }

    func run(_ command: String) async -> ShellResult {
        resolve(command)
    }

    private func resolve(_ command: String) -> ShellResult {
        lock.lock()
        commands.append(command)
        let handler = self.handler
        let result = results[command] ?? defaultResult
        lock.unlock()
        return handler?(command) ?? result
    }
}

@MainActor
final class FakeNginxConfigValidator: NginxConfigValidating {
    var result: NginxValidationResult = .valid
    private(set) var validatedConfigURLs: [URL] = []
    private(set) var validationCount = 0

    func validate(
        configURL: URL,
        prefix: NginxPrefix,
        executableURL: URL
    ) async -> NginxValidationResult {
        validationCount += 1
        validatedConfigURLs.append(configURL)
        return result
    }
}

@MainActor
final class FakeLocalSiteOperations: LocalSiteOperations {
    enum StartOutcome {
        case succeed
        case fail(LocalSiteError)
        case unexpected(any Error)
        case cancel
    }

    var startOutcome: StartOutcome = .succeed
    var rollbackLabels: [String] = []
    var reloadError: Error?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var reloadCalls = 0
    private(set) var executedRollback: [String] = []

    func start(rollback: SiteRollback) async throws {
        startCalls += 1

        for label in rollbackLabels {
            rollback.register(label) { [weak self] in
                self?.executedRollback.append(label)
            }
        }

        switch startOutcome {
        case .succeed:
            return
        case .fail(let error):
            throw error
        case .unexpected(let error):
            throw error
        case .cancel:
            throw CancellationError()
        }
    }

    func stop() async {
        stopCalls += 1
    }

    func reload() async throws {
        reloadCalls += 1
        if let reloadError {
            throw reloadError
        }
    }
}

final class FakeCertificateInspector: CertificateInspecting, @unchecked Sendable {
    private let lock = NSLock()
    private var result = CertificateDetails(
        notAfter: Date(timeIntervalSince1970: 10_000_000),
        domains: []
    )
    private var failure: (any Error)?
    private(set) var inspectedURLs: [URL] = []

    func setResult(_ details: CertificateDetails) {
        lock.lock()
        result = details
        lock.unlock()
    }

    func setFailure(_ error: any Error) {
        lock.lock()
        failure = error
        lock.unlock()
    }

    func details(forCertificateAt url: URL) throws -> CertificateDetails {
        lock.lock()
        defer { lock.unlock() }
        inspectedURLs.append(url)
        if let failure {
            throw failure
        }
        return result
    }
}

final class FakeCertificateTrustEvaluator: CertificateTrustEvaluating, @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private(set) var queriedURLs: [URL] = []

    var trusted: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    func isTrusted(certificateAt url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        queriedURLs.append(url)
        return value
    }
}

@MainActor
final class FakeElevatedShellRunner: ElevatedShellRunning {
    var result = ShellResult(output: "", status: 0)
    var onRun: ((String) -> ShellResult)?
    private(set) var commands: [String] = []

    func run(_ command: String) async -> ShellResult {
        commands.append(command)
        return onRun?(command) ?? result
    }
}

@MainActor
final class FakeNginx: NginxApplying {
    let prefix: NginxPrefix
    var isRunning = false
    var applyError: Error?
    private(set) var applyCalls = 0
    private(set) var appliedSites: [NginxSiteConfiguration] = []
    private(set) var appliedListenPorts: Set<Int> = []
    private(set) var stopCalls = 0

    init(prefix: NginxPrefix) {
        self.prefix = prefix
    }

    func apply(executableURL: URL, sites: [NginxSiteConfiguration], listenPorts: Set<Int>) async throws {
        applyCalls += 1
        if let applyError {
            throw applyError
        }
        appliedSites = sites
        appliedListenPorts = listenPorts
        isRunning = true
    }

    func stop() async {
        stopCalls += 1
        isRunning = false
    }
}

@MainActor
final class FakeFPM: PHPFPMRunning {
    var startError: Error?
    private(set) var configurations: [PHPFPMRuntimeConfiguration] = []
    private(set) var stopCalls = 0

    func start(_ runtime: PHPFPMRuntimeConfiguration) async throws {
        if let startError {
            throw startError
        }
        configurations.append(runtime)
    }

    func stop() async {
        stopCalls += 1
    }
}

@MainActor
final class FakeProxyUpstream: ProxyUpstreamRunning {
    var startError: Error?
    var outputTail: String?
    private(set) var isRunning = false
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var startedSites: [LocalSiteSettings] = []

    func start(site: LocalSiteSettings, workspaceURL: URL) async throws {
        startCalls += 1
        if let startError {
            throw startError
        }
        startedSites.append(site)
        isRunning = true
    }

    func stop() {
        stopCalls += 1
        isRunning = false
    }
}
