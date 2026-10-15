//
//  PHPRuntimeProvider.swift
//  CodeEdit
//
//  Discovers PHP runtimes (managed, brew, system).
//

import Foundation

@MainActor
final class PHPRuntimeProvider: RuntimeProvider {
    let kind: RuntimeKind = .php

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
        guard let formula = version.installIdentifier else {
            throw RuntimeError.unsupported
        }
        progress(.init(phase: .resolving, message: "Preparing \(formula)…"))
        // Stream `brew install` so the user sees activity and can stop it.
        let result = try await RuntimeShell.runStreaming("brew install \(formula)") { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("==>") || trimmed.contains("%") else { return }
            Task { @MainActor in
                progress(.init(phase: .installing, message: trimmed))
            }
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        if result.status != 0 {
            // Homebrew can exit non-zero for benign reasons (auto-update failure, already installed).
            // Only report failure if the version really isn't present.
            if await isInstalled(minorOf: version.version) {
                progress(.init(phase: .done))
                return
            }
            throw RuntimeError.installFailed(
                result.output.isEmpty ? "Homebrew exited with status \(result.status)." : result.output
            )
        }
        progress(.init(phase: .done))
    }

    /// Whether a runtime with the same major.minor version is installed.
    private func isInstalled(minorOf version: String) async -> Bool {
        let minor = version.split(separator: ".").prefix(2).joined(separator: ".")
        return await installedVersions().contains {
            $0.version.split(separator: ".").prefix(2).joined(separator: ".") == minor
        }
    }

    func uninstall(_ runtime: InstalledRuntime) async throws {
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

    /// Runs a command off the main thread.
    private func run(_ command: String) async -> (output: String, status: Int32) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: RuntimeShell.runResult(command))
            }
        }
    }

    func debugger(for runtime: InstalledRuntime) -> RuntimeDebugger? {
        var environment = environment(for: runtime)
        environment["XDEBUG_MODE"] = "debug"
        return RuntimeDebugger(
            kind: .php,
            adapterID: "php",
            adapterCandidates: ["php-debug-adapter", "php-debug", "phpDebug"],
            environment: environment,
            interpreterPath: runtime.executableDirectory.appending(path: "php").path(percentEncoded: false)
        )
    }

    // MARK: - Helpers

    /// Enumerates PHP versions installed via Homebrew under the Cellar.
    private func brewRuntimes() -> [InstalledRuntime] {
        let output = RuntimeShell.lines("""
        prefix="$(brew --prefix 2>/dev/null)"; \
        for d in "$prefix"/Cellar/php "$prefix"/Cellar/php@*; do \
          [ -d "$d" ] || continue; \
          for v in "$d"/*; do \
            [ -x "$v/bin/php" ] && printf '%s\\t%s\\t%s\\n' "$(basename "$d")" "$(basename "$v")" "$v/bin"; \
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
            if let existing = best[runtime.version] {
                if runtime.source.priority < existing.source.priority {
                    best[runtime.version] = runtime
                }
            } else {
                best[runtime.version] = runtime
            }
        }
        return best.values.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}
