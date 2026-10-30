import Combine
import Foundation

@MainActor
final class RuntimeManager: ObservableObject {
    static let shared = RuntimeManager()

    static var runtimesRoot: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".nodalide")
            .appending(path: "runtimes")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    let jobs = RuntimeJobCenter()
    let tooling = RuntimeTooling()

    let runtimesDidChange = PassthroughSubject<RuntimeKind, Never>()

    private(set) var providers: [RuntimeKind: any RuntimeProvider] = [:]

    private init() {
        register(NodeRuntimeProvider())
        register(PHPRuntimeProvider())
        RuntimeCatalog.pruneStaleCache()
    }

    static func isManagedPath(_ url: URL) -> Bool {
        let root = runtimesRoot.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path == root || path.hasPrefix(root + "/")
    }

    // MARK: - Install / uninstall

    func install(kind: RuntimeKind, version: RuntimeVersion, phpOptions: PHPInstallOptions = .default) async {
        guard let provider = provider(for: kind) else { return }
        await jobs.run(kind: kind, version: version.version, operation: .install) { progress in
            if kind == .php, let phpProvider = provider as? PHPRuntimeProvider {
                try await phpProvider.install(version, options: phpOptions, progress: progress)
            } else {
                try await provider.install(version, progress: progress)
            }
        }
        runtimesDidChange.send(kind)
    }

    func uninstall(_ runtime: InstalledRuntime) async {
        guard let provider = provider(for: runtime.kind) else { return }
        await jobs.run(kind: runtime.kind, version: runtime.version, operation: .uninstall) { _ in
            try await provider.uninstall(runtime)
        }
        runtimesDidChange.send(runtime.kind)
    }

    func installXdebug(for runtime: InstalledRuntime) async {
        await jobs.run(kind: .php, version: "xdebug@\(runtime.version)", operation: .install) { progress in
            try await PHPXdebugProvisioner.shared.provision(runtime: runtime, progress: progress)
        }
        runtimesDidChange.send(.php)
    }

    func removeXdebug(from runtime: InstalledRuntime) async {
        await jobs.run(kind: .php, version: "xdebug@\(runtime.version)", operation: .uninstall) { _ in
            try await PHPXdebugProvisioner.shared.remove(runtime: runtime)
        }
        runtimesDidChange.send(.php)
    }

    // MARK: - Node package managers

    func nodePackageManagers(for runtime: InstalledRuntime) async -> [String: String] {
        await NodePackageManagerService.installed(in: runtime)
    }

    func activateNodePackageManager(_ name: String, version: String, runtime: InstalledRuntime) async {
        await jobs.run(kind: runtime.kind, version: "\(name)@\(version)", operation: .install) { progress in
            try await NodePackageManagerService.prepare(name, version: version, in: runtime, progress: progress)
        }
    }

    func register(_ provider: any RuntimeProvider) {
        providers[provider.kind] = provider
    }

    func provider(for kind: RuntimeKind) -> (any RuntimeProvider)? {
        providers[kind]
    }

    var allProviders: [any RuntimeProvider] {
        RuntimeKind.allCases.compactMap { providers[$0] }
    }
}
