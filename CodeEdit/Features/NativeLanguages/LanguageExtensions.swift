//
//  LanguageExtensions.swift
//  CodeEdit
//
//  Declarative language extensions: discovery of `extension.json` packs and loading their
//  symbols into a workspace index.
//

import Foundation
import AppKit
import CodeEditLang

/// The `extension.json` manifest of a declarative language extension.
///
/// Required: `id`, `name`. Everything else is optional. For a pack that contributes anything the
/// `languages` and `contributes` keys are expected too; `author`, `url` and `icon` are display-only.
struct LanguageExtensionManifest: Codable {
    var schemaVersion: Int?
    var id: String
    var name: String
    var version: String?
    var type: String?
    var description: String?
    var author: String?
    var url: String?
    var icon: String?
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
struct InstalledLanguageExtension: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String?
    let root: URL
    let manifest: LanguageExtensionManifest

    /// The framework this pack targets, if any (from `framework` or `activation.framework.requires`).
    var frameworkName: String? { manifest.frameworkName }

    /// A short display line: version and/or author.
    var subtitle: String? {
        [version, manifest.author].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    /// The pack icon (`icon` in the manifest, relative to the pack root) or a default symbol.
    var icon: NSImage {
        if let iconPath = manifest.icon {
            let url = root.appending(path: iconPath)
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        if let symbol = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: nil) {
            return symbol
        }
        return NSImage()
    }

    static func == (lhs: InstalledLanguageExtension, rhs: InstalledLanguageExtension) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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

    // MARK: - Install / remove (global packs)

    /// Installs a pack from a folder containing `extension.json` into the global extensions directory.
    @discardableResult
    func install(fromFolder folder: URL) throws -> InstalledLanguageExtension {
        let data = try Data(contentsOf: folder.appending(path: "extension.json"))
        guard let manifest = try? JSONDecoder().decode(LanguageExtensionManifest.self, from: data) else {
            throw LanguageExtensionInstallError.invalidManifest
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.globalExtensionsDirectory, withIntermediateDirectories: true)
        let destination = Self.globalExtensionsDirectory.appending(path: manifest.id, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: folder, to: destination)
        reload()

        return InstalledLanguageExtension(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            root: destination,
            manifest: manifest
        )
    }

    /// Installs a pack from a `.zip` archive.
    @discardableResult
    func install(fromZip zipURL: URL) throws -> InstalledLanguageExtension {
        let fileManager = FileManager.default
        let tempName = "ce-ext-\(UUID().uuidString)"
        let temp = fileManager.temporaryDirectory.appending(path: tempName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path(percentEncoded: false), "-d", temp.path(percentEncoded: false)]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LanguageExtensionInstallError.unzipFailed
        }
        guard let manifestURL = findManifest(in: temp) else {
            throw LanguageExtensionInstallError.invalidManifest
        }
        return try install(fromFolder: manifestURL.deletingLastPathComponent())
    }

    /// Removes a globally installed pack.
    func remove(_ ext: InstalledLanguageExtension) throws {
        guard ext.root.path(percentEncoded: false)
            .hasPrefix(Self.globalExtensionsDirectory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: ext.root)
        reload()
    }

    /// Finds `extension.json` in a directory (checking the folder and one level of subfolders).
    private func findManifest(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        let direct = directory.appending(path: "extension.json")
        if fileManager.fileExists(atPath: direct.path(percentEncoded: false)) {
            return direct
        }
        let subdirectories = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for subdirectory in subdirectories {
            let candidate = subdirectory.appending(path: "extension.json")
            if fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return nil
    }
}

/// Errors thrown while installing a language extension.
enum LanguageExtensionInstallError: LocalizedError {
    case invalidManifest
    case unzipFailed

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The extension has no valid extension.json manifest."
        case .unzipFailed:
            return "The archive could not be unzipped."
        }
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
        let disabled = Set(Settings.shared.preferences.extensions.disabledExtensions)
        var result: [SymbolInfo] = []

        for ext in LanguageExtensionStore.shared.extensions(forWorkspace: root) {
            guard !disabled.contains(ext.id),
                  ext.manifest.languages?.contains(language) == true,
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

    /// Whether any of the (literal, workspace-relative) activation files exist.
    ///
    /// Activation deliberately never scans the project: a declared project language/framework or a
    /// literal marker file (`wp-config.php`, `artisan`, `composer.json`, …) is enough. Wildcard
    /// patterns are ignored — declare the project language instead.
    private func matchesAnyFile(_ patterns: [String], in root: URL) -> Bool {
        let fileManager = FileManager.default
        return patterns.contains { pattern in
            !pattern.contains("*") && !pattern.contains("?")
                && fileManager.fileExists(atPath: root.appending(path: pattern).path(percentEncoded: false))
        }
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
