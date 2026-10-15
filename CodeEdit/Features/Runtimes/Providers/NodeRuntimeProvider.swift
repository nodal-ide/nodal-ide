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
        runtimes += scanDirectory(
            home.appending(path: ".fnm/node-versions"),
            source: .fnm,
            binSubdir: "installation/bin"
        )
        runtimes += scanDirectory(
            home.appending(path: "Library/Application Support/fnm/node-versions"),
            source: .fnm,
            binSubdir: "installation/bin"
        )
        runtimes += scanDirectory(home.appending(path: ".volta/tools/image/node"), source: .volta)

        for path in RuntimeShell.whichAll("node") {
            let version = RuntimeShell.run("'\(path)' --version")
                .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard !version.isEmpty else { continue }
            let binDirectory = URL(filePath: path).deletingLastPathComponent()
            guard !runtimes.contains(where: { $0.executableDirectory == binDirectory }) else { continue }
            let source: RuntimeVersionSource = path.contains("/Cellar/") || path.contains("/homebrew/")
                ? .brew
                : .system
            runtimes.append(
                InstalledRuntime(
                    kind: .node,
                    version: version,
                    source: source,
                    executableDirectory: binDirectory,
                    installIdentifier: source == .brew ? Self.brewFormula(from: path) : nil
                )
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
        let arch = RuntimeInstaller.architecture
        let fileName = "node-v\(version.version)-darwin-\(arch).tar.gz"
        guard let url = URL(string: "https://nodejs.org/dist/v\(version.version)/\(fileName)") else {
            throw RuntimeError.installFailed("Invalid download URL.")
        }

        progress(.init(phase: .resolving))
        let temporary = FileManager.default.temporaryDirectory.appending(path: fileName)
        try await RuntimeInstaller.download(url, to: temporary) { fraction in
            progress(.init(phase: .downloading, fraction: fraction))
        }
        try Task.checkCancellation()

        progress(.init(phase: .verifying))
        if let expected = await expectedChecksum(version: version.version, fileName: fileName) {
            let actual = try RuntimeInstaller.sha256(of: temporary)
            guard actual == expected else {
                try? FileManager.default.removeItem(at: temporary)
                throw RuntimeError.installFailed("Checksum mismatch.")
            }
        }

        progress(.init(phase: .extracting))
        let extractDirectory = FileManager.default.temporaryDirectory
            .appending(path: "node-extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
        let tempPath = temporary.path(percentEncoded: false)
        let extractPath = extractDirectory.path(percentEncoded: false)
        RuntimeShell.run("tar -xzf '\(tempPath)' -C '\(extractPath)'")

        let extracted = extractDirectory.appending(path: "node-v\(version.version)-darwin-\(arch)")
        guard FileManager.default.fileExists(atPath: extracted.path(percentEncoded: false)) else {
            throw RuntimeError.installFailed("Extraction failed.")
        }

        try Task.checkCancellation()
        progress(.init(phase: .installing))
        let destination = RuntimeManager.runtimesRoot.appending(path: "node").appending(path: version.version)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: extracted, to: destination)

        try? FileManager.default.removeItem(at: temporary)
        try? FileManager.default.removeItem(at: extractDirectory)
        progress(.init(phase: .done))
    }

    /// Reads the expected SHA-256 for a file from Node's `SHASUMS256.txt`.
    private func expectedChecksum(version: String, fileName: String) async -> String? {
        guard let url = URL(string: "https://nodejs.org/dist/v\(version)/SHASUMS256.txt"),
              let data = try? await URLSession.shared.data(from: url).0,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2, parts[1] == Substring(fileName) {
                return String(parts[0])
            }
        }
        return nil
    }

    func uninstall(_ runtime: InstalledRuntime) async throws {
        if runtime.isManaged, RuntimeManager.isManagedPath(runtime.executableDirectory) {
            try FileManager.default.removeItem(at: runtime.executableDirectory.deletingLastPathComponent())
            return
        }
        if runtime.source == .brew, let formula = runtime.installIdentifier {
            let result = RuntimeShell.runResult("brew uninstall \(formula)")
            let stillInstalled = await installedVersions().contains { $0.version == runtime.version }
            if stillInstalled {
                throw RuntimeError.installFailed(
                    result.output.isEmpty ? "Homebrew failed to uninstall \(formula)." : result.output
                )
            }
            return
        }
        throw RuntimeError.installFailed("Only managed or Homebrew runtimes can be removed.")
    }

    /// Extracts the Homebrew formula name from a Cellar binary path (`…/Cellar/<formula>/<version>/bin`).
    private static func brewFormula(from path: String) -> String? {
        let components = URL(filePath: path).pathComponents
        guard let cellarIndex = components.lastIndex(of: "Cellar"), components.count > cellarIndex + 1 else {
            return nil
        }
        return components[cellarIndex + 1]
    }

    func debugger(for runtime: InstalledRuntime) -> RuntimeDebugger? {
        RuntimeDebugger(
            kind: .node,
            adapterID: "node",
            adapterCandidates: ["js-debug", "dapDebugServer", "vscode-js-debug", "node-debug"],
            environment: environment(for: runtime),
            interpreterPath: runtime.executableDirectory.appending(path: "node").path(percentEncoded: false)
        )
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
