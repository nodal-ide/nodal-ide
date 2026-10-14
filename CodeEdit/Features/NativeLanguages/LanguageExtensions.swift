//
//  LanguageExtensions.swift
//  CodeEdit
//
//  Declarative language extensions: discovery of `extension.json` packs and loading their
//  symbols into a workspace index.
//

import Foundation
import CodeEditLang

/// The `extension.json` manifest of a declarative language extension.
struct LanguageExtensionManifest: Codable {
    var schemaVersion: Int?
    var id: String
    var name: String
    var version: String?
    var type: String?
    var description: String?
    var languages: [String]?
    var framework: String?
    var activation: Activation?
    var contributes: Contributes?

    struct Activation: Codable {
        var files: [String]?
        var framework: Framework?

        struct Framework: Codable {
            var file: String?
            var requires: [String: String]?
        }
    }

    struct Contributes: Codable {
        var symbols: [String]?
        var snippets: [String]?
        var stubRoots: [String]?
    }

    /// The framework this pack targets — the top-level `framework`, or the first
    /// `activation.framework.requires` key.
    var frameworkName: String? {
        if let framework, !framework.isEmpty {
            return framework
        }
        return activation?.framework?.requires?.keys.first
    }
}

/// An installed declarative language extension (a pack on disk).
struct InstalledLanguageExtension: Identifiable {
    let id: String
    let name: String
    let version: String?
    let root: URL
    let manifest: LanguageExtensionManifest
}

/// Discovers declarative language extensions from the global Application Support directory and
/// the workspace-local `.codeedit/extensions` directory.
final class LanguageExtensionStore {
    static let shared = LanguageExtensionStore()

    private let lock = NSLock()
    private var globalCache: [InstalledLanguageExtension]?
    private var workspaceCache: [String: [InstalledLanguageExtension]] = [:]

    private init() {}

    /// Global (user-installed) + workspace-local extensions for a workspace root.
    func extensions(forWorkspace root: URL) -> [InstalledLanguageExtension] {
        let key = root.path(percentEncoded: false)
        lock.lock()
        if let cached = workspaceCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var result = globalExtensions()
        result.append(contentsOf: discover(in: root.appending(path: ".codeedit/extensions")))

        lock.lock()
        workspaceCache[key] = result
        lock.unlock()
        return result
    }

    /// Extensions installed globally under `Application Support/CodeEdit/Extensions`.
    func globalExtensions() -> [InstalledLanguageExtension] {
        lock.lock()
        if let cached = globalCache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let listed = discover(in: Self.globalExtensionsDirectory)

        lock.lock()
        globalCache = listed
        lock.unlock()
        return listed
    }

    /// Clears caches so newly added/removed packs are picked up.
    func reload() {
        lock.lock()
        globalCache = nil
        workspaceCache.removeAll()
        lock.unlock()
    }

    private func discover(in directory: URL) -> [InstalledLanguageExtension] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { entry in
            let manifestURL = entry.appending(path: "extension.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(LanguageExtensionManifest.self, from: data) else {
                return nil
            }
            return InstalledLanguageExtension(
                id: manifest.id,
                name: manifest.name,
                version: manifest.version,
                root: entry,
                manifest: manifest
            )
        }
    }

    static var globalExtensionsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "CodeEdit/Extensions", directoryHint: .isDirectory)
    }
}

/// Loads the symbols contributed by declarative language extensions for a workspace and injects
/// them into the workspace `SymbolIndex`.
final class WorkspaceLanguageExtensions {
    static let shared = WorkspaceLanguageExtensions()

    private let lock = NSLock()
    private var symbolCache: [String: [SymbolInfo]] = [:]
    private var injectedRoots: Set<String> = []
    /// Stub files injected per key, so they can be removed before a reload/re-inject.
    private var injectedStubs: [String: [URL]] = [:]

    private init() {}

    /// Injects an extension's symbols into `index` once per (workspace, language).
    ///
    /// Runs off the main thread: pack discovery, parsing and the activation scan are I/O bound and
    /// must never block opening a file.
    func inject(into index: SymbolIndex, root: URL, language: String) {
        let key = "\(root.path(percentEncoded: false))|\(language)"
        lock.lock()
        let alreadyInjected = injectedRoots.contains(key)
        if !alreadyInjected {
            injectedRoots.insert(key)
        }
        lock.unlock()
        guard !alreadyInjected else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let symbols = self.symbols(for: root, language: language)
            guard !symbols.isEmpty else { return }
            index.add(symbols)
            self.lock.lock()
            self.injectedStubs[key] = Array(Set(symbols.map(\.fileURL)))
            self.lock.unlock()
        }
    }

    /// The stub files injected for a workspace (used to remove them before a re-inject).
    func takeInjectedStubURLs(for root: URL) -> [URL] {
        let prefix = "\(root.path(percentEncoded: false))|"
        lock.lock()
        defer { lock.unlock() }
        var urls: [URL] = []
        for (key, stubs) in injectedStubs where key.hasPrefix(prefix) {
            urls.append(contentsOf: stubs)
        }
        return urls
    }

    /// All extension symbols for a workspace + language (cached).
    func symbols(for root: URL, language: String) -> [SymbolInfo] {
        let key = "\(root.path(percentEncoded: false))|\(language)"
        lock.lock()
        if let cached = symbolCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let built = build(root: root, language: language)

        lock.lock()
        symbolCache[key] = built
        lock.unlock()
        return built
    }

    /// Clears caches so reloaded packs are re-read.
    func reload() {
        lock.lock()
        symbolCache.removeAll()
        injectedRoots.removeAll()
        injectedStubs.removeAll()
        lock.unlock()
    }

    private func build(root: URL, language: String) -> [SymbolInfo] {
        let project = loadProjectSettings(in: root)
        var result: [SymbolInfo] = []

        for ext in LanguageExtensionStore.shared.extensions(forWorkspace: root) {
            guard ext.manifest.languages?.contains(language) == true,
                  isActivated(ext, in: root, project: project),
                  let symbolFiles = ext.manifest.contributes?.symbols, !symbolFiles.isEmpty else {
                continue
            }

            var entries: [LanguageSymbolPack.Entry] = []
            for file in symbolFiles {
                let url = ext.root.appending(path: file)
                guard let data = try? Data(contentsOf: url),
                      let pack = try? JSONDecoder().decode(LanguageSymbolPack.self, from: data) else {
                    continue
                }
                entries.append(contentsOf: pack.symbols)
            }
            guard !entries.isEmpty else { continue }

            let stubURL = self.stubURL(for: ext)
            let (text, _) = DeclarativeStub.build(entries: entries)
            try? text.write(to: stubURL, atomically: true, encoding: .utf8)

            let pack = LanguageSymbolPack(language: language, framework: nil, symbols: entries)
            result.append(contentsOf: DeclarativeStub.symbols(from: pack, stubURL: stubURL))
        }

        return result
    }

    /// Whether a pack is active in a workspace.
    ///
    /// 1. If the project declares `frameworks` in `.codeedit/settings.json`, that is authoritative and
    ///    no filesystem scanning happens: framework packs activate only when their framework is
    ///    listed, and language-only packs always activate.
    /// 2. Otherwise, detect from `activation`:
    ///    - `framework`: the marker file (`composer.json` by default) must exist and match `requires`.
    ///    - `files`: at least one workspace file must match a glob (only checked when no framework
    ///      is declared — so framework packs never trigger the scan).
    /// 3. No `activation` block → always active for the language.
    private func isActivated(
        _ ext: InstalledLanguageExtension,
        in root: URL,
        project: ProjectSettings?
    ) -> Bool {
        if let declared = project?.frameworks, !declared.isEmpty {
            guard let name = ext.manifest.frameworkName else { return true }
            return declared.contains { name == $0 || name.contains($0) || $0.contains(name) }
        }

        guard let activation = ext.manifest.activation else { return true }

        if let framework = activation.framework {
            return frameworkMatches(framework, in: root)
        }
        if let files = activation.files, !files.isEmpty {
            return matchesAnyFile(files, in: root)
        }
        return true
    }

    private func loadProjectSettings(in root: URL) -> ProjectSettings? {
        let url = root.appending(path: ".codeedit/settings.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        struct ProjectFile: Codable { var project: ProjectSettings? }
        return (try? JSONDecoder().decode(ProjectFile.self, from: data))?.project
    }

    private func frameworkMatches(
        _ framework: LanguageExtensionManifest.Activation.Framework,
        in root: URL
    ) -> Bool {
        let fileURL = root.appending(path: framework.file ?? "composer.json")
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        guard let requires = framework.requires, !requires.isEmpty else { return true }
        return requires.keys.contains { content.contains($0) }
    }

    /// Matches workspace files against activation globs.
    ///
    /// Literal patterns (no `*`/`?`) are checked with a single `fileExists` at the workspace root —
    /// no enumeration. Only wildcard patterns fall back to a bounded recursive walk.
    private func matchesAnyFile(_ patterns: [String], in root: URL) -> Bool {
        let fileManager = FileManager.default

        var wildcardPatterns: [String] = []
        for pattern in patterns {
            if pattern.contains("*") || pattern.contains("?") {
                wildcardPatterns.append(pattern)
            } else if fileManager.fileExists(atPath: root.appending(path: pattern).path(percentEncoded: false)) {
                return true
            }
        }
        guard !wildcardPatterns.isEmpty else { return false }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        let rootPath = root.path(percentEncoded: false)
        var visited = 0
        let visitLimit = 4000

        for case let url as URL in enumerator {
            visited += 1
            if visited > visitLimit { break }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }

            let path = url.path(percentEncoded: false)
            let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path
            if wildcardPatterns.contains(where: { Glob.matches(pattern: $0, relativePath: relative) }) {
                return true
            }
        }
        return false
    }

    private func stubURL(for ext: InstalledLanguageExtension) -> URL {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: Self.stubCacheDirectory, withIntermediateDirectories: true)
        return Self.stubCacheDirectory.appending(path: "\(ext.id).txt")
    }

    static var stubCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "CodeEdit/ExtensionStubs", directoryHint: .isDirectory)
    }
}

/// Minimal glob matcher for extension activation patterns: `*` (any chars except `/`),
/// `?` (single char), `**` (any chars including `/`).
enum Glob {
    /// Matches a workspace-relative path against a glob pattern. Patterns without `/` match the
    /// file name at any depth.
    static func matches(pattern: String, relativePath: String) -> Bool {
        if !pattern.contains("/") {
            let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
            return regexMatches(pattern, name)
        }
        if regexMatches(pattern, relativePath) {
            return true
        }
        // `**/name.ext` should also match a root-level `name.ext`.
        if pattern.hasPrefix("**/") {
            return regexMatches(String(pattern.dropFirst(3)), relativePath)
        }
        return false
    }

    private static func regexMatches(_ pattern: String, _ string: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: globToRegex(pattern)) else { return false }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }

    private static func globToRegex(_ pattern: String) -> String {
        var regex = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let char = pattern[index]
            if char == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    index = pattern.index(after: next)
                    continue
                }
                regex += "[^/]*"
            } else if char == "?" {
                regex += "[^/]"
            } else if "\\^$.|+()[]{}".contains(char) {
                regex += "\\\(char)"
            } else {
                regex.append(char)
            }
            index = pattern.index(after: index)
        }
        return regex + "$"
    }
}
