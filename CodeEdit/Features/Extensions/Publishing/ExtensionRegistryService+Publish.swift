//
//  ExtensionRegistryService+Publish.swift
//  CodeEdit
//
//  Review preparation and the commit/push half of publishing.
//

import CodeEditLang
import Foundation

extension ExtensionRegistryService {
    func preparePublish(
        configuration: ExtensionRegistryConfiguration,
        packageAt root: URL,
        scope: LanguageExtensionPackScope = .global
    ) async throws -> ExtensionPublishPreparation {
        let snapshot = try await publicationSnapshot(configuration: configuration)
        let artifact = try await builder.build(packageAt: root, scope: scope)
        var keepArtifact = false
        defer {
            if !keepArtifact {
                artifact.removeTemporaryFiles()
            }
        }

        let release = try ExtensionRegistryRelease(manifest: artifact.manifest)
        guard ExtensionCatalogValidator.isRegistryExtensionID(release.manifest.id) else {
            throw ExtensionRegistryError.invalidManifest(
                "`id` must be a reverse-DNS identifier such as com.example.language."
            )
        }
        let preparation = try await makePreparation(
            snapshot: snapshot,
            artifact: artifact,
            release: release
        )
        keepArtifact = true
        return preparation
    }

    func publish(
        preparation: ExtensionPublishPreparation,
        pushAfterCommit: Bool
    ) async throws -> ExtensionPublishResult {
        guard !isPublishing else {
            throw ExtensionRegistryError.invalidConfiguration("Another publish is already in progress.")
        }
        isPublishing = true
        defer { isPublishing = false }
        defer { preparation.artifact.removeTemporaryFiles() }

        if pushAfterCommit, preparation.remote == nil {
            throw ExtensionRegistryError.noRemote
        }
        let (repositoryRoot, branch) = try await validatePreparation(preparation)
        let commitSHA = try await writeAndCommit(preparation, repositoryRoot: repositoryRoot)

        if !pushAfterCommit {
            return ExtensionPublishResult(
                preparation: preparation,
                outcome: .committedLocally(commitSHA: commitSHA)
            )
        }
        return try await pushOrRecord(
            preparation,
            repositoryRoot: repositoryRoot,
            branch: branch,
            commitSHA: commitSHA
        )
    }

    private func publicationSnapshot(
        configuration: ExtensionRegistryConfiguration
    ) async throws -> ExtensionRegistrySnapshot {
        let snapshot = try await inspect(configuration: configuration)
        if let pending = snapshot.pendingPush {
            throw ExtensionRegistryError.pendingPublish(
                "Commit \(String(pending.commitSHA.prefix(8))) for \(pending.extensionID) "
                    + "\(pending.version) is waiting to be pushed."
            )
        }
        guard snapshot.catalogExists else {
            throw ExtensionRegistryError.missingCatalog(
                "The registry has no extensions.json. Recreate or repair the registry first."
            )
        }
        guard snapshot.commitIdentity != nil else {
            throw ExtensionRegistryError.invalidConfiguration(
                "Git has no commit identity. Set user.name and user.email for this repository first."
            )
        }
        if let conflict = snapshot.changes.first(where: \.isConflicted) {
            throw ExtensionRegistryError.unmergedPaths([conflict.path])
        }
        return snapshot
    }

    private func makePreparation(
        snapshot: ExtensionRegistrySnapshot,
        artifact: ExtensionPackageArtifact,
        release: ExtensionRegistryRelease
    ) async throws -> ExtensionPublishPreparation {
        let paths = try publishPaths(for: release, in: snapshot.repositoryRoot)
        try verifyPublishable(snapshot, paths: paths)
        let update: ExtensionCatalogUpdate = try await catalogUpdate(
            catalogURL: paths.catalogURL,
            release: release,
            packageRelativePath: paths.packageRelativePath,
            integrity: artifact.integrity,
            temporaryDirectory: artifact.temporaryDirectory
        )
        let remote = try await configurationRemote(
            configuration: snapshot.configuration,
            snapshot: snapshot
        )

        return ExtensionPublishPreparation(
            id: UUID(),
            configuration: snapshot.configuration,
            repositoryRoot: snapshot.repositoryRoot,
            catalogURL: paths.catalogURL,
            catalogRelativePath: paths.catalogRelativePath,
            catalogBefore: update.before,
            catalogAfter: update.after,
            catalogDiff: update.diff,
            packageRelativePath: paths.packageRelativePath,
            packageURL: paths.packageURL,
            artifact: artifact,
            release: release,
            branch: snapshot.branch ?? snapshot.configuration.branch,
            remote: remote,
            headSHA: snapshot.headSHA,
            commitIdentity: snapshot.commitIdentity ?? "",
            unrelatedChanges: snapshot.changes.filter {
                !paths.isGenerated($0.path)
            },
            latestAdvanced: update.latestAdvanced,
            createdAt: .now
        )
    }

    private func publishPaths(
        for release: ExtensionRegistryRelease,
        in repositoryRoot: URL
    ) throws -> ExtensionPublishPaths {
        let catalogRelativePath = ExtensionRegistryCatalogDocument.catalogFileName
        let packageDirectoryRelativePath = "extensions/\(release.manifest.id)/\(release.manifest.version)"
        let packageRelativePath = "\(packageDirectoryRelativePath)/\(release.manifest.version).zip"
        return ExtensionPublishPaths(
            catalogRelativePath: catalogRelativePath,
            packageDirectoryRelativePath: packageDirectoryRelativePath,
            packageRelativePath: packageRelativePath,
            catalogURL: try containedURL(for: catalogRelativePath, in: repositoryRoot),
            packageURL: try containedURL(for: packageRelativePath, in: repositoryRoot),
            extensionID: release.manifest.id,
            version: release.manifest.version
        )
    }

    private func verifyPublishable(
        _ snapshot: ExtensionRegistrySnapshot,
        paths: ExtensionPublishPaths
    ) throws {
        guard !FileManager.default.fileExists(atPath: paths.packageURL.path(percentEncoded: false)) else {
            throw ExtensionRegistryError.duplicateVersion(
                extensionID: paths.extensionID,
                version: paths.version
            )
        }
        let catalogData = try Data(contentsOf: paths.catalogURL)
        let allowUntrackedCatalog = snapshot.changes.contains {
            $0.path == paths.catalogRelativePath && $0.code == "??"
        } && catalogData == ExtensionRegistryCatalogDocument.emptyCatalogData()
        try verifyNoConflictingChanges(
            snapshot.changes,
            catalog: paths.catalogRelativePath,
            packageDirectory: paths.packageDirectoryRelativePath,
            allowUntrackedCatalog: allowUntrackedCatalog
        )
    }

    private func catalogUpdate(
        catalogURL: URL,
        release: ExtensionRegistryRelease,
        packageRelativePath: String,
        integrity: String,
        temporaryDirectory: URL
    ) async throws -> ExtensionCatalogUpdate {
        let catalogBeforeData = try Data(contentsOf: catalogURL)
        let document = try ExtensionRegistryCatalogDocument(data: catalogBeforeData)
        guard !document.contains(extensionID: release.manifest.id, version: release.manifest.version) else {
            throw ExtensionRegistryError.duplicateVersion(
                extensionID: release.manifest.id,
                version: release.manifest.version
            )
        }
        let mutation = try document.addingRelease(
            release,
            packageURL: packageRelativePath,
            integrity: integrity
        )
        let before = String(bytes: catalogBeforeData, encoding: .utf8) ?? ""
        let after = String(bytes: mutation.data, encoding: .utf8) ?? ""
        let diff = try await catalogDiff(
            before: before,
            after: after,
            in: temporaryDirectory
        )
        return ExtensionCatalogUpdate(
            before: before,
            after: after,
            diff: diff,
            latestAdvanced: mutation.latestAdvanced
        )
    }

    private func verifyNoConflictingChanges(
        _ changes: [ExtensionRegistryGitChange],
        catalog: String,
        packageDirectory: String,
        allowUntrackedCatalog: Bool
    ) throws {
        let conflicting = changes.filter {
            ($0.path == catalog && !allowUntrackedCatalog)
                || $0.path == packageDirectory
                || $0.path.hasPrefix(packageDirectory + "/")
        }
        if !conflicting.isEmpty {
            throw ExtensionRegistryError.dirtyPaths(conflicting.map(\.path))
        }
    }

    private func validatePreparation(
        _ preparation: ExtensionPublishPreparation
    ) async throws -> (URL, String) {
        let repositoryRoot = try await git.repositoryRoot(at: preparation.configuration.workingCopyURL)
        guard repositoryRoot == preparation.repositoryRoot else {
            throw ExtensionRegistryError.staleReview("The registry moved.")
        }
        let currentHead = try await git.headSHA(in: repositoryRoot)
        guard currentHead == preparation.headSHA else {
            throw ExtensionRegistryError.staleReview("The repository has a new commit.")
        }
        let branch = try await git.branch(in: repositoryRoot) ?? preparation.branch
        guard branch == preparation.branch else {
            throw ExtensionRegistryError.staleReview("The current branch changed.")
        }
        if try loadJournal(for: repositoryRoot) != nil {
            throw ExtensionRegistryError.pendingPublish("Push the previous commit before publishing again.")
        }
        let currentCatalog = try Data(contentsOf: preparation.catalogURL)
        guard currentCatalog == Data(preparation.catalogBefore.utf8) else {
            throw ExtensionRegistryError.staleReview("extensions.json changed after review.")
        }
        guard !FileManager.default.fileExists(atPath: preparation.packageURL.path(percentEncoded: false)) else {
            throw ExtensionRegistryError.duplicateVersion(
                extensionID: preparation.extensionID,
                version: preparation.version
            )
        }
        return (repositoryRoot, branch)
    }

    private func writeAndCommit(
        _ preparation: ExtensionPublishPreparation,
        repositoryRoot: URL
    ) async throws -> String {
        let packageDirectory = preparation.packageURL.deletingLastPathComponent()
        let packageDirectoryExisted = FileManager.default.fileExists(
            atPath: packageDirectory.path(percentEncoded: false)
        )
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        let stagingPackage = packageDirectory.appending(
            path: ".\(preparation.version).\(UUID().uuidString).tmp"
        )
        var staged = false
        var commitSHA: String?
        do {
            try writeFiles(preparation, stagingPackage: stagingPackage)
            let paths = [preparation.catalogRelativePath, preparation.packageRelativePath]
            try await git.add(paths: paths, in: repositoryRoot)
            staged = true
            let created = try await git.commit(
                paths: paths,
                message: "Add \(preparation.extensionID) \(preparation.version)",
                in: repositoryRoot
            )
            commitSHA = created
            let committedFiles = Set(try await git.commitFiles(created, in: repositoryRoot))
            guard committedFiles == Set(paths) else {
                throw ExtensionRegistryError.ioFailure(
                    "The commit included unexpected files: "
                        + "\(committedFiles.sorted().joined(separator: ", ")). "
                        + "Inspect commit \(created) before pushing."
                )
            }
            return created
        } catch {
            if commitSHA == nil {
                await rollbackFiles(
                    preparation,
                    repositoryRoot: repositoryRoot,
                    staged: staged,
                    packageDirectoryExisted: packageDirectoryExisted
                )
            }
            try? FileManager.default.removeItem(at: stagingPackage)
            throw error
        }
    }

    private func writeFiles(
        _ preparation: ExtensionPublishPreparation,
        stagingPackage: URL
    ) throws {
        try FileManager.default.copyItem(at: preparation.artifact.archiveURL, to: stagingPackage)
        guard try fileSHA256(stagingPackage) == preparation.artifact.integrity else {
            throw ExtensionRegistryError.archiveFailed("The reviewed ZIP changed before publishing.")
        }
        try FileManager.default.moveItem(at: stagingPackage, to: preparation.packageURL)
        try Data(preparation.catalogAfter.utf8).write(to: preparation.catalogURL, options: [.atomic])
        try ExtensionRegistryCatalogDocument.validateCatalogData(
            Data(contentsOf: preparation.catalogURL)
        )
    }

    private func rollbackFiles(
        _ preparation: ExtensionPublishPreparation,
        repositoryRoot: URL,
        staged: Bool,
        packageDirectoryExisted: Bool
    ) async {
        let paths = [preparation.catalogRelativePath, preparation.packageRelativePath]
        if staged {
            try? await git.reset(paths: paths, in: repositoryRoot)
        }
        try? Data(preparation.catalogBefore.utf8).write(
            to: preparation.catalogURL,
            options: [.atomic]
        )
        if FileManager.default.fileExists(atPath: preparation.packageURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: preparation.packageURL)
        }
        if !packageDirectoryExisted {
            try? FileManager.default.removeItem(at: preparation.packageURL.deletingLastPathComponent())
        }
    }

    private func pushOrRecord(
        _ preparation: ExtensionPublishPreparation,
        repositoryRoot: URL,
        branch: String,
        commitSHA: String
    ) async throws -> ExtensionPublishResult {
        guard let remote = preparation.remote else {
            throw ExtensionRegistryError.noRemote
        }
        do {
            _ = try await git.push(branch: branch, remote: remote, in: repositoryRoot)
            try? removeJournal(for: repositoryRoot)
            return ExtensionPublishResult(
                preparation: preparation,
                outcome: .pushed(commitSHA: commitSHA)
            )
        } catch {
            let journal = ExtensionPublishJournal(
                workingCopyPath: preparation.configuration.workingCopyPath,
                repositoryRootPath: repositoryRoot.path(percentEncoded: false),
                catalogRelativePath: preparation.catalogRelativePath,
                packageRelativePath: preparation.packageRelativePath,
                extensionID: preparation.extensionID,
                version: preparation.version,
                integrity: preparation.artifact.integrity,
                branch: branch,
                remote: remote,
                commitSHA: commitSHA,
                createdAt: .now
            )
            let retryNote: String
            do {
                try saveJournal(journal)
                retryNote = ""
            } catch {
                retryNote = " The retry record could not be saved: \(error.localizedDescription)"
            }
            return ExtensionPublishResult(
                preparation: preparation,
                outcome: .pushFailed(
                    commitSHA: commitSHA,
                    message: error.localizedDescription + retryNote
                )
            )
        }
    }
}
