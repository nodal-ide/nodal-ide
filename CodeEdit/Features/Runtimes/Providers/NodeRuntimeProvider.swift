//
//  NodeRuntimeProvider.swift
//  CodeEdit
//
//  Discovers Node.js runtimes (managed, nvm, fnm, volta, brew, system).
//

import Foundation

@MainActor
final class NodeRuntimeProvider: RuntimeProvider {
    let kind: RuntimeKind = .node

    func installedVersions() async -> [InstalledRuntime] {
        var runtimes: [InstalledRuntime] = []

        let home = FileManager.default.homeDirectoryForCurrentUser
        runtimes += scanDirectory(RuntimeManager.runtimesRoot.appending(path: "node"), source: .managed)
        runtimes += scanDirectory(home.appending(path: ".nvm/versions/node"), source: .nvm)
        runtimes += scanDirectory(home.appending(path: ".fnm/node-versions"), source: .fnm, binSubdir: "installation/bin")
        runtimes += scanDirectory(
            home.appending(path: "Library/Application Support/fnm/node-versions"), source: .fnm, binSubdir: "installation/bin"
        )
        runtimes += scanDirectory(home.appending(path: ".volta/tools/image/node"), source: .volta)

        for path in RuntimeShell.whichAll("node") {
            let version = RuntimeShell.run("'\(path)' --version")
                .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard !version.isEmpty else { continue }
            let binDirectory = URL(filePath: path).deletingLastPathComponent()
            guard !runtimes.contains(where: { $0.executableDirectory == binDirectory }) else { continue }
            let source: RuntimeVersionSource = path.contains("/Cellar/") || path.contains("/homebrew/") ? .brew : .system
            runtimes.append(
                InstalledRuntime(kind: .node, version: version, source: source, executableDirectory: binDirectory)
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

    private func scanDirectory(
        _ root: URL,
        source: RuntimeVersionSource,
        binSubdir: String = "bin"
    ) -> [InstalledRuntime] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { entry in
            let version = entry.lastPathComponent.hasPrefix("v")
                ? String(entry.lastPathComponent.dropFirst())
                : entry.lastPathComponent
            let bin = entry.appending(path: binSubdir)
            guard FileManager.default.fileExists(atPath: bin.path(percentEncoded: false)) else { return nil }
            return InstalledRuntime(kind: kind, version: version, source: source, executableDirectory: bin)
        }
    }

    private func deduped(_ runtimes: [InstalledRuntime]) -> [InstalledRuntime] {
        var seen = Set<String>()
        return runtimes
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}
