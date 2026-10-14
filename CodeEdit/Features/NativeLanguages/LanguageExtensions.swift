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

    private init() {}

    /// Injects an extension's symbols into `index` once per (workspace, language).
    func inject(into index: SymbolIndex, root: URL, language: String) {
        let key = "\(root.path(percentEncoded: false))|\(language)"
        lock.lock()
        let alreadyInjected = injectedRoots.contains(key)
        if !alreadyInjected {
            injectedRoots.insert(key)
        }
        lock.unlock()
        guard !alreadyInjected else { return }

        let symbols = symbols(for: root, language: language)
        if !symbols.isEmpty {
            index.add(symbols)
        }
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
        lock.unlock()
    }

    private func build(root: URL, language: String) -> [SymbolInfo] {
        var result: [SymbolInfo] = []

        for ext in LanguageExtensionStore.shared.extensions(forWorkspace: root) {
            guard ext.manifest.languages?.contains(language) == true,
                  isActivated(ext, in: root),
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

    /// A pack is active when it has no framework requirement, or the requirement's file mentions
    /// one of the required package names (e.g. `composer.json` requiring `laravel/framework`).
    private func isActivated(_ ext: InstalledLanguageExtension, in root: URL) -> Bool {
        guard let framework = ext.manifest.activation?.framework else { return true }
        let fileURL = root.appending(path: framework.file ?? "composer.json")
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        guard let requires = framework.requires, !requires.isEmpty else { return true }
        return requires.keys.contains { content.contains($0) }
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
