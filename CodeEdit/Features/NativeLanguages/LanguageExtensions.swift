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
import os

private let languageExtensionsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "",
    category: "LanguageExtensions"
)

/// Decodes a JSON file, logging read/decode failures (only when the file actually exists).
private func loadJSONFile<T: Decodable>(_ type: T.Type, from url: URL, descriptor: String) -> T? {
    let fileManager = FileManager.default
    guard let data = try? Data(contentsOf: url) else {
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            languageExtensionsLogger.error(
                "Failed to read \(descriptor, privacy: .public) at \(url.path, privacy: .public)"
            )
        }
        return nil
    }
    guard let value = try? JSONDecoder().decode(T.self, from: data) else {
        languageExtensionsLogger.error(
            "Failed to decode \(descriptor, privacy: .public) at \(url.path, privacy: .public)"
        )
        return nil
    }
    return value
}

/// `LanguageExtensionManifest` (the `extension.json` model) lives in `CodeEditLang` so the app and
/// the `codeedit-ext` authoring tool share it.

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
            if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
                languageExtensionsLogger.error(
                    "Failed to list extensions in \(directory.path, privacy: .public)"
                )
            }
            return []
        }

        return entries.compactMap { entry in
            let manifestURL = entry.appending(path: "extension.json")
            guard let manifest = loadJSONFile(
                LanguageExtensionManifest.self, from: manifestURL, descriptor: "manifest"
            ) else {
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
        defer {
            do {
                try fileManager.removeItem(at: temp)
            } catch {
                languageExtensionsLogger.warning(
                    "Failed to remove temporary unzip directory: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

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
        if subdirectories.isEmpty {
            languageExtensionsLogger.warning(
                "No subdirectories while searching for extension.json in \(directory.path, privacy: .public)"
            )
        }
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
        var result: [SymbolInfo] = []

        for ext in AppServices.languageExtensionStore.extensions(forWorkspace: root) {
            guard LanguageExtensionActivation.isEnabled(ext),
                  ext.manifest.languages?.contains(language) == true,
                  LanguageExtensionActivation.isActivated(ext, in: root),
                  let symbolFiles = ext.manifest.contributes?.symbols, !symbolFiles.isEmpty else {
                continue
            }

            var entries: [LanguageSymbolPack.Entry] = []
            for file in symbolFiles {
                let url = ext.root.appending(path: file)
                guard let pack = loadJSONFile(
                    LanguageSymbolPack.self, from: url, descriptor: "symbol pack"
                ) else {
                    continue
                }
                entries.append(contentsOf: pack.symbols)
            }
            guard !entries.isEmpty else { continue }

            let stubURL = self.stubURL(for: ext)
            let (text, _) = DeclarativeStub.build(entries: entries)
            do {
                try text.write(to: stubURL, atomically: true, encoding: .utf8)
            } catch {
                languageExtensionsLogger.error(
                    "Failed to write symbol stub: \(error.localizedDescription, privacy: .public)"
                )
            }

            let pack = LanguageSymbolPack(language: language, framework: nil, symbols: entries)
            result.append(contentsOf: DeclarativeStub.symbols(from: pack, stubURL: stubURL))
        }

        return result
    }

    private func stubURL(for ext: InstalledLanguageExtension) -> URL {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: Self.stubCacheDirectory, withIntermediateDirectories: true)
        } catch {
            languageExtensionsLogger.error(
                "Failed to create stub cache directory: \(error.localizedDescription, privacy: .public)"
            )
        }
        return Self.stubCacheDirectory.appending(path: "\(ext.id).txt")
    }

    static var stubCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "CodeEdit/ExtensionStubs", directoryHint: .isDirectory)
    }
}
