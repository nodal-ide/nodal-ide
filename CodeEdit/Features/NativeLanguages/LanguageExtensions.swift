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

let languageExtensionsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "",
    category: "LanguageExtensions"
)

/// Decodes a JSON file, logging read/decode failures (only when the file actually exists).
func loadJSONFile<T: Decodable>(_ type: T.Type, from url: URL, descriptor: String) -> T? {
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

    /// Clears cached symbols and injections for one workspace only.
    func reload(root: URL) {
        let prefix = "\(root.path(percentEncoded: false))|"
        lock.lock()
        symbolCache = symbolCache.filter { !$0.key.hasPrefix(prefix) }
        injectedRoots = injectedRoots.filter { !$0.hasPrefix(prefix) }
        injectedStubs = injectedStubs.filter { !$0.key.hasPrefix(prefix) }
        lock.unlock()
    }

    private func build(root: URL, language: String) -> [SymbolInfo] {
        var result: [SymbolInfo] = []

        for ext in AppServices.languageExtensionStore.extensions(forWorkspace: root) {
            guard LanguageExtensionActivation.isEnabled(ext, in: root),
                  ext.manifest.languages?.contains(language) == true,
                  LanguageExtensionActivation.isActivated(ext, in: root),
                  let symbolFiles = ext.manifest.contributes?.symbols, !symbolFiles.isEmpty else {
                continue
            }

            var entries: [LanguageSymbolPack.Entry] = []
            for file in symbolFiles {
                guard let url = LanguageExtensionPaths.resolve(file, in: ext.root),
                      LanguageExtensionPaths.isContained(url, in: ext.root) else { continue }
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
        let safeID = ext.id
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return Self.stubCacheDirectory.appending(path: "\(safeID).txt")
    }

    static var stubCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "CodeEdit/ExtensionStubs", directoryHint: .isDirectory)
    }
}
