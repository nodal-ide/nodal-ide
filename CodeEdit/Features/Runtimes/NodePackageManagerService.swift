//
//  NodePackageManagerService.swift
//  CodeEdit
//
//  Detects and prepares Node package managers (npm/pnpm/yarn) for a runtime via corepack.
//

import Foundation

@MainActor
enum NodePackageManagerService {
    /// Package managers we surface (npm ships with Node; pnpm/yarn are managed by corepack).
    static let known = ["npm", "pnpm", "yarn"]

    /// Installed package managers and their versions for a Node runtime.
    static func installed(in runtime: InstalledRuntime) async -> [String: String] {
        var result: [String: String] = [:]
        for name in known {
            let version = await run("\(name) --version", in: runtime)
            if !version.isEmpty {
                result[name] = version.split(separator: "\n").last.map(String.init) ?? version
            }
        }
        return result
    }

    /// Downloads and activates a package manager version for a runtime using corepack.
    static func prepare(
        _ packageManager: String,
        version: String,
        in runtime: InstalledRuntime,
        progress: @escaping (RuntimeInstallProgress) -> Void
    ) async throws {
        progress(.init(phase: .installing, message: "corepack prepare \(packageManager)@\(version)"))
        let result = await runResult(
            "corepack prepare \(packageManager)@\(version) --activate",
            in: runtime
        )
        guard result.status == 0 else {
            throw RuntimeError.installFailed(result.output.isEmpty ? "corepack failed." : result.output)
        }
        progress(.init(phase: .done))
    }

    // MARK: - Helpers

    private static func run(_ command: String, in runtime: InstalledRuntime) async -> String {
        await runResult(command, in: runtime).output
    }

    private static func runResult(
        _ command: String,
        in runtime: InstalledRuntime
    ) async -> (output: String, status: Int32) {
        let bin = runtime.executableDirectory.path(percentEncoded: false)
        let full = "export PATH=\"\(bin):$PATH\"; \(command)"
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: RuntimeShell.runResult(full))
            }
        }
    }
}
