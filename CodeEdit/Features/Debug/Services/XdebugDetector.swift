import Combine
import Foundation
import SwiftUI

@MainActor
final class XdebugDetector: ObservableObject {
    static let shared = XdebugDetector()

    enum Status: Equatable {
        case unknown
        case checking
        case noPHP
        case notInstalled(php: String)
        case loaded(php: String, version: String, mode: String, workspaceName: String?)
    }

    @Published private(set) var status: Status = .unknown

    private var cancellables = Set<AnyCancellable>()

    private init() {
        AppServices.runtimeManager.runtimesDidChange
            .filter { $0 == .php }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refresh() }
            }
            .store(in: &cancellables)
    }

    func refresh(workspace: WorkspaceDocument? = nil) async {
        status = .checking
        guard let resolved = await Self.resolvedPHP(workspace: workspace) else {
            status = .noPHP
            return
        }
        let php = resolved.path
        let scanDirArg: String
        if let scanDir = resolved.scanDir {
            scanDirArg = "-d php_ini_scan_dir='\(scanDir)' "
        } else {
            scanDirArg = ""
        }

        let version = await Self.run(
            "'\(php)' \(scanDirArg)-r 'echo extension_loaded(\"xdebug\") ? phpversion(\"xdebug\") : \"\";' 2>/dev/null"
        )
        guard !version.isEmpty else {
            status = .notInstalled(php: php)
            return
        }
        let info = await Self.run("'\(php)' \(scanDirArg)-i 2>/dev/null")
        let mode = Self.value(of: "xdebug.mode", in: info) ?? "off"
        let workspaceName = workspace?.fileURL?.lastPathComponent
        status = .loaded(php: php, version: version, mode: mode, workspaceName: workspaceName)
    }

    static func phpExecutable(workspace: WorkspaceDocument?) async -> String? {
        (await resolvedPHP(workspace: workspace))?.path
    }

    private static func resolvedPHP(workspace: WorkspaceDocument?) async -> (path: String, scanDir: String?)? {
        if let runtime = await RuntimeResolver.resolve(kind: .php, workspace: workspace) {
            let path = runtime.executableDirectory.appending(path: "php").path(percentEncoded: false)
            let scanDir = PHPXdebugProvisioner.shared.iniScanDir(for: runtime)
            return (path, scanDir)
        }
        if let systemPath = RuntimeShell.whichAll("php").first {
            return (systemPath, nil)
        }
        return nil
    }

    static func value(of key: String, in phpInfo: String) -> String? {
        for line in phpInfo.split(separator: "\n") {
            let parts = line.split(separator: "=>").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count >= 2, parts[0].caseInsensitiveCompare(key) == .orderedSame {
                return parts[1]
            }
        }
        return nil
    }

    private static func run(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: RuntimeShell.run(command))
            }
        }
    }
}
