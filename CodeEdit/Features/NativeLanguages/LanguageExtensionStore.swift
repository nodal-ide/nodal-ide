//
//  LanguageExtensionStore.swift
//  CodeEdit
//
//  Discovery and transactional installation of global language extension packs.
//

import Foundation
import AppKit
import CodeEditLang
import os

/// Discovers declarative language extensions from the global Application Support directory and
/// the workspace-local `.codeedit/extensions` directory.
final class LanguageExtensionStore: @unchecked Sendable {
    static let shared = LanguageExtensionStore()

    let extensionsDirectory: URL

    private let lock = NSLock()
    private let mutationLock = NSLock()
    private var globalCache: [InstalledLanguageExtension]?
    private var workspaceCache: [String: [InstalledLanguageExtension]] = [:]

    init(extensionsDirectory: URL = LanguageExtensionStore.globalExtensionsDirectory) {
        self.extensionsDirectory = extensionsDirectory
    }

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
        result.append(contentsOf: discover(in: root.appending(path: ".codeedit/extensions"), scope: .workspace))

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

        let listed = discover(in: extensionsDirectory, scope: .global)

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

    private func discover(in directory: URL, scope: LanguageExtensionPackScope) -> [InstalledLanguageExtension] {
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
            let provenance = ExtensionProvenance.load(from: entry).flatMap { provenance in
                provenance.extensionID == manifest.id && provenance.version == manifest.version
                    ? provenance
                    : nil
            }
            return InstalledLanguageExtension(
                id: manifest.id,
                name: manifest.name,
                version: manifest.version,
                root: entry,
                manifest: manifest,
                scope: scope,
                provenance: provenance
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
        try install(packageAt: folder)
    }

    /// Installs a validated package transactionally.
    ///
    /// The package is staged next to the installed directory, checked against the expected catalog
    /// identity, then atomically swapped in. An existing pack is only replaced after the new one has
    /// passed every check, so a failed update leaves the previous pack usable.
    @discardableResult
    func install(
        packageAt folder: URL,
        provenance: ExtensionProvenance? = nil,
        expectedIdentity: ExtensionPackageIdentity? = nil
    ) throws -> InstalledLanguageExtension {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let manifest = try validatedManifest(packageAt: folder, expectedIdentity: expectedIdentity)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
        let resolvedExtensionsDirectory = extensionsDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL

        // Defense in depth: never hand a manifest-controlled path to a filesystem operation.
        guard let destination = LanguageExtensionPaths.resolve(manifest.id, in: resolvedExtensionsDirectory) else {
            throw LanguageExtensionInstallError.invalidManifest
        }

        let stagingRoot = resolvedExtensionsDirectory
            .appending(path: ".staging", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stagedPack = stagingRoot.appending(path: "package", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try fileManager.copyItem(at: folder, to: stagedPack)
        ExtensionProvenance.remove(from: stagedPack)
        if let provenance {
            try provenance.write(to: stagedPack)
        }
        try ensureNoSymbolicLinks(in: stagedPack)

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.replaceItemAt(destination, withItemAt: stagedPack)
        } else {
            try fileManager.moveItem(at: stagedPack, to: destination)
        }
        reload()

        return InstalledLanguageExtension(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            root: destination,
            manifest: manifest,
            scope: .global,
            provenance: provenance
        )
    }

    private func validatedManifest(
        packageAt folder: URL,
        expectedIdentity: ExtensionPackageIdentity?
    ) throws -> LanguageExtensionManifest {
        let data = try Data(contentsOf: folder.appending(path: "extension.json"))
        guard let manifest = try? JSONDecoder().decode(LanguageExtensionManifest.self, from: data) else {
            throw LanguageExtensionInstallError.invalidManifest
        }
        if let expectedIdentity {
            guard manifest.id == expectedIdentity.extensionID else {
                throw LanguageExtensionInstallError.identityMismatch(
                    expected: expectedIdentity.extensionID,
                    actual: manifest.id
                )
            }
            if let expectedVersion = expectedIdentity.version, manifest.version != expectedVersion {
                throw LanguageExtensionInstallError.versionMismatch(
                    expected: expectedVersion,
                    actual: manifest.version ?? "none"
                )
            }
        }

        let validation = LanguageExtensionValidator.validate(
            manifest: manifest,
            root: folder,
            context: validationContext(for: .global)
        )
        guard validation.isValid else {
            throw LanguageExtensionInstallError.validationFailed(validation.errors)
        }
        return manifest
    }

    private func validationContext(for scope: LanguageExtensionPackScope) -> LanguageExtensionValidationContext {
        LanguageExtensionValidationContext(
            known: SyntaxContributionLoader.knownLanguages(in: .builtIn),
            allowsNativeGrammars: true,
            scope: scope,
            hostVersion: Bundle.versionString
        )
    }

    private func ensureNoSymbolicLinks(in root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys
        ) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                throw LanguageExtensionInstallError.unsafePackage(
                    "The package contains a symbolic link at \(url.lastPathComponent)."
                )
            }
        }
    }

    /// Installs a pack from a `.zip` archive.
    @discardableResult
    func install(fromZip zipURL: URL) throws -> InstalledLanguageExtension {
        let fileManager = FileManager.default
        let temp = fileManager.temporaryDirectory.appending(
            path: "ce-ext-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
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

        let packRoot = try ExtensionArchiveExtractor().extract(
            archiveAt: zipURL,
            to: temp.appending(path: "contents", directoryHint: .isDirectory)
        )
        return try install(packageAt: packRoot)
    }

    /// Removes a globally installed pack.
    func remove(_ ext: InstalledLanguageExtension) throws {
        mutationLock.lock()
        defer { mutationLock.unlock() }
        guard LanguageExtensionPaths.isContained(ext.root, in: extensionsDirectory) else { return }
        try FileManager.default.removeItem(at: ext.root)
        reload()
    }

}

/// Errors thrown while installing a language extension.
enum LanguageExtensionInstallError: LocalizedError {
    case invalidManifest
    case validationFailed([LanguageExtensionIssue])
    case identityMismatch(expected: String, actual: String)
    case versionMismatch(expected: String, actual: String)
    case unsafePackage(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The extension has no valid extension.json manifest."
        case let .validationFailed(issues):
            return "The extension is invalid:\n" + issues.map(\.description).joined(separator: "\n")
        case let .identityMismatch(expected, actual):
            return "The package is for \(actual), but the catalog expected \(expected)."
        case let .versionMismatch(expected, actual):
            return "The package version is \(actual), but the catalog expected \(expected)."
        case let .unsafePackage(message):
            return message
        }
    }
}
