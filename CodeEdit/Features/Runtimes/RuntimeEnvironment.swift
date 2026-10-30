import Combine
import Foundation

@MainActor
final class RuntimeEnvironment: ObservableObject {
    static let shared = RuntimeEnvironment()

    private var cache: [String: [String: String]] = [:]

    private init() {}

    func refresh(workspace: WorkspaceDocument) async {
        var binPaths: [String] = []
        var extraEnv: [String: String] = [:]

        for kind in RuntimeKind.manageable {
            if let runtime = await RuntimeResolver.resolve(kind: kind, workspace: workspace) {
                binPaths.append(runtime.executableDirectory.path(percentEncoded: false))
                if kind == .php, let scanDir = PHPXdebugProvisioner.shared.iniScanDir(for: runtime) {
                    extraEnv["PHP_INI_SCAN_DIR"] = scanDir
                }
            }
        }

        var environment: [String: String] = extraEnv
        if !binPaths.isEmpty {
            environment["CE_RUNTIME_PATH"] = binPaths.joined(separator: ":")

            var parts = binPaths
            for dir in RuntimeShell.extraPathDirectories where !parts.contains(dir) {
                parts.append(dir)
            }
            let existing = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            for dir in existing where !parts.contains(dir) {
                parts.append(dir)
            }
            environment["PATH"] = parts.joined(separator: ":")
        }

        if let path = workspace.fileURL?.path(percentEncoded: false) {
            cache[path] = environment
        }
    }

    func cachedEnvironment(for workspaceURL: URL?) -> [String: String] {
        guard let path = workspaceURL?.path(percentEncoded: false) else { return [:] }
        return cache[path] ?? [:]
    }
}
