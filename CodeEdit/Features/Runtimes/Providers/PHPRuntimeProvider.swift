import Foundation
import OSLog

@MainActor
final class PHPRuntimeProvider: RuntimeProvider {
    let kind: RuntimeKind = .php

    private static let logger = Logger(subsystem: "do.upper.nodalide", category: "PHPRuntimeProvider")

    func installedVersions() async -> [InstalledRuntime] {
        var runtimes: [InstalledRuntime] = []
        runtimes += scanDirectory(RuntimeManager.runtimesRoot.appending(path: "php"), source: .managed)
        runtimes += brewRuntimes()
        for path in RuntimeShell.whichAll("php") {
            let version = phpVersion(at: path)
            guard !version.isEmpty else { continue }
            let binDirectory = URL(filePath: path).deletingLastPathComponent()
            guard !runtimes.contains(where: { $0.executableDirectory == binDirectory }) else { continue }
            runtimes.append(
                InstalledRuntime(kind: .php, version: version, source: .system, executableDirectory: binDirectory)
            )
        }
        return deduped(runtimes)
    }

    func availableVersions() async -> [RuntimeVersion] {
        let installed = await installedVersions()
        let versions = await RuntimeCatalog.versions(for: kind)
        return annotate(versions, installed: installed)
    }

    func install(_ version: RuntimeVersion, progress: @escaping (RuntimeInstallProgress) -> Void) async throws {
        try await install(version, options: .default, progress: progress)
    }

    func install(
        _ version: RuntimeVersion,
        options: PHPInstallOptions,
        progress: @escaping (RuntimeInstallProgress) -> Void
    ) async throws {
        guard let formula = version.installIdentifier else {
            throw RuntimeError.unsupported
        }
        progress(.init(phase: .resolving, message: "Preparing \(formula)…"))
        let result = try await RuntimeShell.runStreaming("brew install \(formula)") { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("==>") || trimmed.contains("%") else { return }
            Task { @MainActor in
                progress(.init(phase: .installing, message: trimmed))
            }
        }

        if Task.isCancelled { throw CancellationError() }

        if result.status != 0 {
            if await isInstalled(minorOf: version.version) {
                progress(.init(phase: .done))
            } else {
                throw RuntimeError.installFailed(
                    result.output.isEmpty ? "Homebrew exited with status \(result.status)." : result.output
                )
            }
        }

        if options.installXdebug, let runtime = await resolvedRuntime(for: version) {
            do {
                try await PHPXdebugProvisioner.shared.provision(runtime: runtime, progress: progress)
            } catch {
                Self.logger.warning(
                    "Xdebug provisioning failed for PHP \(version.version, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                progress(.init(phase: .done, message: "PHP installed. Xdebug setup failed — retry in Runtime Manager."))
                return
            }
        }

        progress(.init(phase: .done))
    }

    func uninstall(_ runtime: InstalledRuntime) async throws {
        if runtime.source == .brew || runtime.source == .managed {
            try? await PHPXdebugProvisioner.shared.remove(runtime: runtime)
        }
        if runtime.isManaged, RuntimeManager.isManagedPath(runtime.executableDirectory) {
            try FileManager.default.removeItem(at: runtime.executableDirectory.deletingLastPathComponent())
            return
        }
        if runtime.source == .brew, let formula = runtime.installIdentifier {
            let result = await run("brew uninstall \(formula)")
            if await isInstalled(minorOf: runtime.version) {
                throw RuntimeError.installFailed(
                    result.output.isEmpty ? "Homebrew failed to uninstall \(formula)." : result.output
                )
            }
            return
        }
        throw RuntimeError.installFailed("Only managed or Homebrew runtimes can be removed.")
    }

    func environment(for runtime: InstalledRuntime) -> [String: String] {
        let bin = runtime.executableDirectory.path(percentEncoded: false)
        var env: [String: String] = [
            "PATH": bin + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")
        ]
        if let scanDir = PHPXdebugProvisioner.shared.iniScanDir(for: runtime) {
            env["PHP_INI_SCAN_DIR"] = scanDir
        }
        return env
    }

    func debugger(for runtime: InstalledRuntime) -> RuntimeDebugger? {
        var environment = environment(for: runtime)
        let port = AppServices.settings.preferences.developerSettings.phpDebugClientPort
        environment["XDEBUG_MODE"] = "debug"
        environment["XDEBUG_CONFIG"] = "client_port=\(port) start_with_request=yes"
        return RuntimeDebugger(
            kind: .php,
            adapterID: "php",
            adapterCandidates: ["php-debug-adapter", "php-debug", "phpDebug"],
            environment: environment,
            interpreterPath: runtime.executableDirectory.appending(path: "php").path(percentEncoded: false)
        )
    }

    // MARK: - Helpers

    private func isInstalled(minorOf version: String) async -> Bool {
        let minor = version.split(separator: ".").prefix(2).joined(separator: ".")
        return await installedVersions().contains {
            $0.version.split(separator: ".").prefix(2).joined(separator: ".") == minor
        }
    }

    private func resolvedRuntime(for version: RuntimeVersion) async -> InstalledRuntime? {
        let minor = version.version.split(separator: ".").prefix(2).joined(separator: ".")
        return await installedVersions().first {
            $0.version.split(separator: ".").prefix(2).joined(separator: ".") == minor
        }
    }

    private func run(_ command: String) async -> (output: String, status: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: RuntimeShell.runResult(command))
            }
        }
    }

    private func brewRuntimes() -> [InstalledRuntime] {
        let output = RuntimeShell.lines("""
        prefix="$(brew --prefix 2>/dev/null)"; \
        for d in "$prefix"/Cellar/php "$prefix"/Cellar/php@*; do \
          [ -d "$d" ] || continue; \
          for v in "$d"/*; do \
            [ -x "$v/bin/php" ] && printf '%s\t%s\t%s\n' "$(basename "$d")" "$(basename "$v")" "$v/bin"; \
          done; \
        done
        """)
        return output.compactMap { line in
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count == 3 else { return nil }
            return InstalledRuntime(
                kind: kind,
                version: parts[1],
                source: .brew,
                executableDirectory: URL(filePath: parts[2]),
                installIdentifier: parts[0]
            )
        }
    }

    private func phpVersion(at path: String) -> String {
        let output = RuntimeShell.run("'\(path)' -r 'echo PHP_VERSION;'")
        return output.split(separator: "\n").last.map(String.init) ?? ""
    }

    private func scanDirectory(_ root: URL, source: RuntimeVersionSource) -> [InstalledRuntime] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { entry in
            let bin = entry.appending(path: "bin")
            guard FileManager.default.fileExists(atPath: bin.path(percentEncoded: false)) else { return nil }
            return InstalledRuntime(
                kind: kind,
                version: entry.lastPathComponent,
                source: source,
                executableDirectory: bin
            )
        }
    }

    private func deduped(_ runtimes: [InstalledRuntime]) -> [InstalledRuntime] {
        var best: [String: InstalledRuntime] = [:]
        for runtime in runtimes {
            let key = Self.baseVersion(runtime.version)
            if let existing = best[key] {
                let prefer = runtime.source.priority < existing.source.priority
                    || (runtime.source.priority == existing.source.priority
                        && Self.revisionNumber(runtime.version) > Self.revisionNumber(existing.version))
                if prefer {
                    best[key] = runtime
                }
            } else {
                best[key] = runtime
            }
        }
        return best.values.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    private static func baseVersion(_ version: String) -> String {
        guard let underscore = version.lastIndex(of: "_") else { return version }
        let after = version[version.index(after: underscore)...]
        guard after.allSatisfy(\.isNumber) else { return version }
        return String(version[..<underscore])
    }

    private static func revisionNumber(_ version: String) -> Int {
        guard let underscore = version.lastIndex(of: "_") else { return 0 }
        let after = version[version.index(after: underscore)...]
        return Int(after) ?? 0
    }
}
