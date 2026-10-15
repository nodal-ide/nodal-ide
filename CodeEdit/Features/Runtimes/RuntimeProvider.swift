//
//  RuntimeProvider.swift
//  CodeEdit
//
//  The SPI a runtime manager provider implements (one per runtime kind).
//

import Foundation

/// A provider for a single web runtime: discovery, catalog, install/uninstall, and environment.
///
/// Providers are registered with ``RuntimeManager``. Concrete providers live in the app (e.g. Node, PHP).
@MainActor
protocol RuntimeProvider: AnyObject {
    var kind: RuntimeKind { get }

    /// Runtimes present on the system (managed, adopted from brew/nvm, or system).
    func installedVersions() async -> [InstalledRuntime]

    /// Versions available to install (from an upstream catalog), annotated with installed state.
    func availableVersions() async -> [RuntimeVersion]

    /// Installs a version into the managed directory, reporting progress.
    /// - Parameters:
    ///   - version: The version to install (from ``availableVersions()``).
    ///   - progress: Called with progress updates.
    func install(_ version: RuntimeVersion, progress: @escaping (RuntimeInstallProgress) -> Void) async throws

    /// Removes a managed runtime. Adopted (non-managed) runtimes are not removed.
    func uninstall(_ runtime: InstalledRuntime) async throws

    /// The environment (e.g. a `PATH` prepend) to run tools with this runtime.
    func environment(for runtime: InstalledRuntime) -> [String: String]
}

extension RuntimeProvider {
    func environment(for runtime: InstalledRuntime) -> [String: String] {
        let bin = runtime.executableDirectory.path(percentEncoded: false)
        return ["PATH": bin + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")]
    }

    /// Marks catalog versions that are installed on the system.
    func annotate(_ versions: [RuntimeVersion], installed: [InstalledRuntime]) -> [RuntimeVersion] {
        let byVersion = Dictionary(grouping: installed, by: \.version)
        return versions.map { version in
            var version = version
            version.installedSource = byVersion[version.version]?.first?.source
            return version
        }
    }
}

enum RuntimeError: LocalizedError {
    case unsupported
    case notFound(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "This runtime is not supported."
        case .notFound(let name): return "Could not find \(name)."
        case .installFailed(let reason): return "Installation failed: \(reason)"
        }
    }
}
