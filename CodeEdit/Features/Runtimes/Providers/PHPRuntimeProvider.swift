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
        [] // RM3 (catalog)
    }

    func install(version: String, progress: @escaping (RuntimeInstallProgress) -> Void) async throws {
        throw RuntimeError.unsupported // RM4
    }

    func uninstall(_ runtime: InstalledRuntime) async throws {
        guard runtime.isManaged else {
            throw RuntimeError.installFailed("Only managed runtimes can be removed.")
        }
        try FileManager.default.removeItem(at: runtime.executableDirectory.deletingLastPathComponent())
    }

    // MARK: - Helpers

    /// Enumerates PHP versions installed via Homebrew under the Cellar.
    private func brewRuntimes() -> [InstalledRuntime] {
        let output = RuntimeShell.lines("""
        prefix="$(brew --prefix 2>/dev/null)"; \
        for d in "$prefix"/Cellar/php "$prefix"/Cellar/php@*; do \
          [ -d "$d" ] || continue; \
          for v in "$d"/*; do [ -x "$v/bin/php" ] && printf '%s\\t%s\\n' "$(basename "$v")" "$v/bin"; done; \
        done
        """)
        return output.compactMap { line in
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count == 2 else { return nil }
            return InstalledRuntime(
                kind: kind,
                version: parts[0],
                source: .brew,
                executableDirectory: URL(filePath: parts[1])
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
        var seen = Set<String>()
        return runtimes
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}
