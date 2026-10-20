import Foundation

/// A PHP runtime that can actually serve a local site: the interpreter plus a matching php-fpm.
struct LocalSiteRuntime: Identifiable, Equatable, Sendable {
    let runtime: InstalledRuntime
    let installation: PHPFPMInstallation

    var id: String { runtime.id }
    var version: String { runtime.version }
    var source: RuntimeVersionSource { runtime.source }
}

/// Resolves which installed PHP runtimes can back a local site. FPM availability is a capability of a
/// runtime, so the site picker must only offer versions where a matching php-fpm was detected.
@MainActor
final class PHPFPMRuntimeCatalog {
    private let detector: any PHPFPMDetecting

    init(detector: (any PHPFPMDetecting)? = nil) {
        self.detector = detector ?? PHPFPMDetector()
    }

    /// Detects FPM for every installed runtime, keyed by ``InstalledRuntime/id``.
    func statuses(for runtimes: [InstalledRuntime]) async -> [String: PHPFPMStatus] {
        var statuses: [String: PHPFPMStatus] = [:]
        for runtime in runtimes {
            statuses[runtime.id] = await detector.status(for: runtime)
        }
        return statuses
    }

    /// The runtimes with a matching php-fpm, newest first.
    func usableRuntimes(from runtimes: [InstalledRuntime]) async -> [LocalSiteRuntime] {
        var usable: [LocalSiteRuntime] = []
        for runtime in runtimes {
            if case let .available(installation) = await detector.status(for: runtime) {
                usable.append(LocalSiteRuntime(runtime: runtime, installation: installation))
            }
        }
        return usable.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    func usableRuntimes(using provider: any RuntimeProvider) async -> [LocalSiteRuntime] {
        await usableRuntimes(from: await provider.installedVersions())
    }

    /// The requested version when usable, the newest usable runtime when no version is specified, or
    /// `nil` when a pinned version is not usable (so a site never silently runs a different PHP).
    func resolve(version: String?, from runtimes: [InstalledRuntime]) async -> LocalSiteRuntime? {
        let usable = await usableRuntimes(from: runtimes)
        if let version, !version.isEmpty {
            return usable.first { $0.version == version }
        }
        return usable.first
    }
}
