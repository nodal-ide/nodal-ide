//
//  ExtensionRegistryService.swift
//  CodeEdit
//
//  Creates registries and commits verified extension releases without touching unrelated work.
//

import CodeEditLang
import Foundation

actor ExtensionRegistryService {
    let git = RegistryGitClient()
    let builder = ExtensionPackageBuilder()
    let runner = CommandRunner()
    let journalDirectory: URL
    var isPublishing = false

    init(journalDirectory: URL? = nil) {
        self.journalDirectory = journalDirectory ?? Self.defaultJournalDirectory()
    }

    func inspect(configuration: ExtensionRegistryConfiguration) async throws -> ExtensionRegistrySnapshot {
        let repositoryRoot = try await git.repositoryRoot(at: configuration.workingCopyURL)
        let branch = try await git.branch(in: repositoryRoot)
        let headSHA = try await git.headSHA(in: repositoryRoot)
        let remoteURL = try await git.remoteURL(in: repositoryRoot)
        let identity = try await git.commitIdentity(in: repositoryRoot)
        let changes = try await git.status(in: repositoryRoot)
        let catalogURL = repositoryRoot.appending(path: ExtensionRegistryCatalogDocument.catalogFileName)
        let catalogExists = FileManager.default.fileExists(
            atPath: catalogURL.path(percentEncoded: false)
        )
        let extensionCount = try extensionCount(at: catalogURL)

        return ExtensionRegistrySnapshot(
            configuration: configuration,
            repositoryRoot: repositoryRoot,
            branch: branch,
            remoteURL: remoteURL,
            headSHA: headSHA,
            commitIdentity: identity,
            changes: changes,
            catalogURL: catalogURL,
            catalogExists: catalogExists,
            extensionCount: extensionCount,
            pendingPush: try? loadJournal(for: repositoryRoot)
        )
    }

    func initialize(
        workingCopy: URL,
        name: String,
        cloneURL: String?,
        branch requestedBranch: String,
        catalogURL: String?
    ) async throws -> ExtensionRegistrySnapshot {
        let branch = requestedBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let repositoryRoot = try await prepareRepository(
            at: workingCopy.standardizedFileURL,
            cloneURL: cloneURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            branch: branch
        )
        try createInitialFilesIfNeeded(in: repositoryRoot, name: name)

        let remoteURL = try await git.remoteURL(in: repositoryRoot)
        let actualBranch = try await git.branch(in: repositoryRoot) ?? branch
        let trimmedCatalogURL = catalogURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let inferredCatalogURL = ExtensionRegistryLocations
            .inferCatalogURL(remoteURL: remoteURL, branch: actualBranch)?.absoluteString
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuration = ExtensionRegistryConfiguration(
            workingCopy: repositoryRoot,
            name: trimmedName.isEmpty ? repositoryRoot.lastPathComponent : trimmedName,
            branch: actualBranch,
            remote: remoteURL == nil ? nil : "origin",
            catalogURL: trimmedCatalogURL.isEmpty ? inferredCatalogURL : trimmedCatalogURL
        )
        return try await inspect(configuration: configuration)
    }

    private func prepareRepository(at target: URL, cloneURL: String, branch: String) async throws -> URL {
        let fileManager = FileManager.default
        if !cloneURL.isEmpty {
            try prepareForClone(at: target)
            let parent = target.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let targetPath = target.path(percentEncoded: false)
            _ = try await git.run(["clone", "--", cloneURL, targetPath], in: parent)
            try await checkOutOrCreate(branch: branch, in: target)
        } else {
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            let existingRoot = try? await git.repositoryRoot(at: target)
            if existingRoot != target {
                var arguments = ["init"]
                if !branch.isEmpty {
                    arguments += ["-b", branch]
                }
                _ = try await git.run(arguments, in: target)
            }
        }

        let repositoryRoot = try await git.repositoryRoot(at: target)
        guard repositoryRoot == target else {
            throw ExtensionRegistryError.invalidConfiguration(
                "Choose a folder that is its own Git repository, not part of a parent repository."
            )
        }
        return repositoryRoot
    }

    private func extensionCount(at catalogURL: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: catalogURL.path(percentEncoded: false)) else {
            return 0
        }
        let document = try ExtensionRegistryCatalogDocument(data: Data(contentsOf: catalogURL))
        return document.extensionCount
    }

    private static func defaultJournalDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: "Nodal", directoryHint: .isDirectory)
            .appending(path: "ExtensionPublishing", directoryHint: .isDirectory)
    }
}
