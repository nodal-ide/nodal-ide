//
//  ExtensionPackageBuilder.swift
//  CodeEdit
//
//  Builds and verifies the ZIP that is stored in a registry and downloaded by clients.
//

import CodeEditLang
import CryptoKit
import Foundation

struct ExtensionPackageBuilder: Sendable {
    private static let excludedPatterns = [
        ".DS_Store",
        "*.DS_Store",
        ".git/*",
        "*/.git/*",
        "__MACOSX/*",
        "*/.build/*",
        "*/.swiftpm/*",
        "*.tmp"
    ]

    private let runner = CommandRunner()
    private let extractor = ExtensionArchiveExtractor()

    func build(
        packageAt root: URL,
        scope: LanguageExtensionPackScope = .global
    ) async throws -> ExtensionPackageArtifact {
        let sourceRoot = root.standardizedFileURL
        let manifest = try loadManifest(at: sourceRoot)
        try validate(sourceRoot, scope: scope)

        let version = manifest.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard ExtensionRegistryCatalogDocument.isSemVer(version) else {
            throw ExtensionRegistryError.invalidManifest(
                "`version` must be Semantic Versioning (for example 1.2.3)."
            )
        }
        try rejectSymbolicLinks(in: sourceRoot)
        return try await createArtifact(
            sourceRoot: sourceRoot,
            manifest: manifest,
            version: version
        )
    }

    private func loadManifest(at root: URL) throws -> LanguageExtensionManifest {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path(percentEncoded: false)) else {
            throw ExtensionRegistryError.invalidManifest("The package folder no longer exists.")
        }
        let manifestURL = root.appending(path: "extension.json")
        guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else {
            throw ExtensionRegistryError.invalidManifest("The package folder has no extension.json.")
        }
        do {
            return try JSONDecoder().decode(
                LanguageExtensionManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw ExtensionRegistryError.invalidManifest(
                "extension.json is invalid: \(error.localizedDescription)"
            )
        }
    }

    private func validate(_ root: URL, scope: LanguageExtensionPackScope) throws {
        let validation = LanguageExtensionValidator.validate(
            packAt: root,
            context: .init(
                allowsNativeGrammars: scope == .global,
                scope: scope
            )
        )
        guard validation.isValid else {
            throw ExtensionRegistryError.validationFailed(validation.errors)
        }
    }

    private func createArtifact(
        sourceRoot: URL,
        manifest: LanguageExtensionManifest,
        version: String
    ) async throws -> ExtensionPackageArtifact {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appending(path: "NodalExtensionPublish-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        var succeeded = false
        defer {
            if !succeeded {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        let archiveURL = temporaryDirectory.appending(path: "\(version).zip")
        try await createZip(sourceRoot: sourceRoot, archiveURL: archiveURL)
        let size = try archiveSize(archiveURL)
        try verifyArchive(
            archiveURL,
            in: temporaryDirectory,
            manifest: manifest,
            version: version
        )

        let digest = SHA256.hash(data: try Data(contentsOf: archiveURL, options: [.mappedIfSafe]))
        let integrity = digest.map { String(format: "%02x", $0) }.joined()
        let summary = ExtensionManifestSummary(
            id: manifest.id,
            name: manifest.name,
            version: version,
            description: manifest.description,
            author: manifest.author,
            url: manifest.url
        )

        succeeded = true
        return ExtensionPackageArtifact(
            temporaryDirectory: temporaryDirectory,
            archiveURL: archiveURL,
            byteCount: size,
            integrity: integrity,
            manifest: summary
        )
    }

    private func createZip(sourceRoot: URL, archiveURL: URL) async throws {
        var arguments = ["-X", "-r", "-q", archiveURL.path(percentEncoded: false), "."]
        arguments += ["-x"]
        arguments += Self.excludedPatterns
        _ = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: arguments,
            currentDirectory: sourceRoot
        )
    }

    private func archiveSize(_ archiveURL: URL) throws -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: archiveURL.path(percentEncoded: false)
        ), let size = (attributes[.size] as? NSNumber)?.intValue, size > 0 else {
            throw ExtensionRegistryError.archiveFailed("The ZIP is empty.")
        }
        return size
    }

    private func verifyArchive(
        _ archiveURL: URL,
        in temporaryDirectory: URL,
        manifest: LanguageExtensionManifest,
        version: String
    ) throws {
        let extracted = temporaryDirectory.appending(path: "Verified", directoryHint: .isDirectory)
        let extractedRoot: URL
        do {
            extractedRoot = try extractor.extract(archiveAt: archiveURL, to: extracted)
        } catch {
            throw ExtensionRegistryError.archiveFailed(error.localizedDescription)
        }

        let verifiedManifest: LanguageExtensionManifest
        do {
            verifiedManifest = try JSONDecoder().decode(
                LanguageExtensionManifest.self,
                from: Data(contentsOf: extractedRoot.appending(path: "extension.json"))
            )
        } catch {
            throw ExtensionRegistryError.archiveFailed("The archive manifest could not be read.")
        }
        guard verifiedManifest.id == manifest.id,
              verifiedManifest.version == version else {
            throw ExtensionRegistryError.archiveFailed(
                "The archive contains a different extension or version."
            )
        }
    }

    private func rejectSymbolicLinks(in root: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw ExtensionRegistryError.archiveFailed("Could not inspect the package folder.")
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                throw ExtensionRegistryError.invalidManifest(
                    "Remove the symbolic link \(url.lastPathComponent); packages must be self-contained."
                )
            }
        }
    }
}
