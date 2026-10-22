//
//  ExtensionRegistryService+Retry.swift
//  CodeEdit
//
//  Re-pushes a commit that was created before a network failure.
//

import Foundation

extension ExtensionRegistryService {
    func retryPendingPush(configuration: ExtensionRegistryConfiguration) async throws -> String {
        guard !isPublishing else {
            throw ExtensionRegistryError.invalidConfiguration("Another publish is already in progress.")
        }
        isPublishing = true
        defer { isPublishing = false }

        let repositoryRoot = try await git.repositoryRoot(at: configuration.workingCopyURL)
        guard let journal = try loadJournal(for: repositoryRoot) else {
            throw ExtensionRegistryError.noPendingPublish
        }
        guard let head = try await git.headSHA(in: repositoryRoot), head == journal.commitSHA else {
            throw ExtensionRegistryError.staleReview("HEAD no longer points at the pending publish commit.")
        }
        guard let branch = try await git.branch(in: repositoryRoot), branch == journal.branch else {
            throw ExtensionRegistryError.staleReview("The current branch changed.")
        }
        try validateJournalContents(journal, repositoryRoot: repositoryRoot)
        guard let remote = journal.remote else {
            throw ExtensionRegistryError.noRemote
        }
        _ = try await git.push(branch: branch, remote: remote, in: repositoryRoot)
        try removeJournal(for: repositoryRoot)
        return journal.commitSHA
    }

    private func validateJournalContents(
        _ journal: ExtensionPublishJournal,
        repositoryRoot: URL
    ) throws {
        let packageURL = try containedURL(for: journal.packageRelativePath, in: repositoryRoot)
        guard try fileSHA256(packageURL) == journal.integrity else {
            throw ExtensionRegistryError.staleReview("The published ZIP no longer matches the journal.")
        }
        let catalogURL = try containedURL(for: journal.catalogRelativePath, in: repositoryRoot)
        let document = try ExtensionRegistryCatalogDocument(data: Data(contentsOf: catalogURL))
        guard document.integrity(extensionID: journal.extensionID, version: journal.version)
            == journal.integrity else {
            throw ExtensionRegistryError.staleReview("The pending catalog entry changed.")
        }
    }
}
