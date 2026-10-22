//
//  ExtensionRegistryModels.swift
//  CodeEdit
//
//  Value types shared by registry setup, publishing, and their views.
//

import CodeEditLang
import Foundation

struct ExtensionRegistryConfiguration: Codable, Hashable, Sendable, Identifiable {
    var id: String { workingCopyPath }
    var workingCopyPath: String
    var name: String
    var branch: String
    var remote: String?
    var catalogURL: String?

    var workingCopyURL: URL {
        URL(filePath: workingCopyPath, directoryHint: .isDirectory)
    }

    var catalogWebURL: URL? {
        catalogURL.flatMap(URL.init(string:))
    }

    init(
        workingCopyPath: String,
        name: String,
        branch: String = "main",
        remote: String? = nil,
        catalogURL: String? = nil
    ) {
        self.workingCopyPath = workingCopyPath
        self.name = name
        self.branch = branch
        self.remote = remote
        self.catalogURL = catalogURL
    }

    init(workingCopy: URL, name: String? = nil, branch: String, remote: String?, catalogURL: String?) {
        let standardized = workingCopy.standardizedFileURL
        self.workingCopyPath = standardized.path(percentEncoded: false)
        self.name = name ?? standardized.lastPathComponent
        self.branch = branch
        self.remote = remote
        self.catalogURL = catalogURL
    }
}

struct ExtensionRegistryGitChange: Hashable, Sendable, Identifiable {
    var id: String { "\(code):\(path)" }
    let code: String
    let path: String

    var isConflicted: Bool {
        code.contains("U") || code == "AA" || code == "DD"
    }
}

struct ExtensionRegistrySnapshot: Sendable {
    let configuration: ExtensionRegistryConfiguration
    let repositoryRoot: URL
    let branch: String?
    let remoteURL: String?
    let headSHA: String?
    let commitIdentity: String?
    let changes: [ExtensionRegistryGitChange]
    let catalogURL: URL
    let catalogExists: Bool
    let extensionCount: Int
    let pendingPush: ExtensionPublishJournal?

    var isClean: Bool {
        changes.isEmpty
    }
}

struct ExtensionManifestSummary: Sendable, Equatable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let author: String?
    let url: String?
}

struct ExtensionPackageArtifact: Sendable {
    let temporaryDirectory: URL
    let archiveURL: URL
    let byteCount: Int
    let integrity: String
    let manifest: ExtensionManifestSummary

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

struct ExtensionRegistryRelease: Sendable, Equatable {
    let manifest: ExtensionManifestSummary
    let catalogName: String
    let catalogDescription: String
    let catalogPublisher: String
    let catalogHomepage: URL?

    init(manifest: ExtensionManifestSummary) throws {
        let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (manifest.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let publisher = (manifest.author ?? "Unknown").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, name.utf8.count <= 128 else {
            throw ExtensionRegistryError.invalidManifest(
                "`name` must contain between 1 and 128 bytes."
            )
        }
        guard !description.isEmpty, description.utf8.count <= 4_096 else {
            throw ExtensionRegistryError.invalidManifest(
                "Add a `description` of at most 4096 bytes before publishing."
            )
        }
        guard !publisher.isEmpty, publisher.utf8.count <= 128 else {
            throw ExtensionRegistryError.invalidManifest(
                "`author` must contain between 1 and 128 bytes."
            )
        }

        var homepage: URL?
        if let rawURL = manifest.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty {
            guard let url = URL(string: rawURL), url.scheme?.lowercased() == "https",
                  url.host != nil, url.user == nil, url.password == nil else {
                throw ExtensionRegistryError.invalidManifest(
                    "`url` must be an HTTPS URL without credentials."
                )
            }
            homepage = url
        }

        self.manifest = manifest
        self.catalogName = name
        self.catalogDescription = description
        self.catalogPublisher = publisher
        self.catalogHomepage = homepage
    }
}

struct ExtensionPublishPreparation: Sendable, Identifiable {
    let id: UUID
    let configuration: ExtensionRegistryConfiguration
    let repositoryRoot: URL
    let catalogURL: URL
    let catalogRelativePath: String
    let catalogBefore: String
    let catalogAfter: String
    let catalogDiff: String
    let packageRelativePath: String
    let packageURL: URL
    let artifact: ExtensionPackageArtifact
    let release: ExtensionRegistryRelease
    let branch: String
    let remote: String?
    let headSHA: String?
    let commitIdentity: String
    let unrelatedChanges: [ExtensionRegistryGitChange]
    let latestAdvanced: Bool
    let createdAt: Date

    var extensionID: String { release.manifest.id }
    var version: String { release.manifest.version }
}

enum ExtensionPublishOutcome: Sendable, Equatable {
    case committedLocally(commitSHA: String)
    case pushed(commitSHA: String)
    case pushFailed(commitSHA: String, message: String)
}

struct ExtensionPublishResult: Sendable {
    let preparation: ExtensionPublishPreparation
    let outcome: ExtensionPublishOutcome
}

struct ExtensionPublishJournal: Codable, Hashable, Sendable, Identifiable {
    var id: String { workingCopyPath + ":" + commitSHA }
    let workingCopyPath: String
    let repositoryRootPath: String
    let catalogRelativePath: String
    let packageRelativePath: String
    let extensionID: String
    let version: String
    let integrity: String
    let branch: String
    let remote: String?
    let commitSHA: String
    let createdAt: Date
}

enum ExtensionRegistryError: LocalizedError {
    case invalidConfiguration(String)
    case notARepository(URL)
    case missingCatalog(String)
    case invalidCatalog(String)
    case invalidManifest(String)
    case validationFailed([LanguageExtensionIssue])
    case duplicateVersion(extensionID: String, version: String)
    case dirtyPaths([String])
    case unmergedPaths([String])
    case unsafePath(String)
    case archiveFailed(String)
    case staleReview(String)
    case noRemote
    case pendingPublish(String)
    case noPendingPublish
    case command(String)
    case ioFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .notARepository(let url):
            return "\(url.lastPathComponent) is not a Git repository."
        case .missingCatalog(let message):
            return message
        case .invalidCatalog(let message):
            return "The registry catalog is invalid: \(message)"
        case .invalidManifest(let message):
            return "The extension manifest is not ready to publish: \(message)"
        case .validationFailed(let issues):
            let details = issues.map(\.description).joined(separator: "\n")
            return "The extension failed validation:\n\(details)"
        case let .duplicateVersion(extensionID, version):
            return "\(extensionID) version \(version) already exists in the registry. "
                + "Increment the manifest version before publishing."
        case .dirtyPaths(let paths):
            return "Save or commit these registry changes first: \(paths.joined(separator: ", "))."
        case .unmergedPaths(let paths):
            return "Resolve merge conflicts before publishing: \(paths.joined(separator: ", "))."
        case .unsafePath(let path):
            return "The registry path is unsafe: \(path)"
        case .archiveFailed(let message):
            return "Couldn’t create a valid extension package: \(message)"
        case .staleReview(let message):
            return "The registry changed after review. Review the publish again. \(message)"
        case .noRemote:
            return "This registry has no Git remote. Add an `origin` remote or commit locally only."
        case .pendingPublish(let message):
            return "A previous publish is waiting to be pushed. \(message)"
        case .noPendingPublish:
            return "There is no pending publish to retry."
        case .command(let message):
            return message
        case .ioFailure(let message):
            return message
        }
    }
}

struct ExtensionPublishPaths {
    let catalogRelativePath: String
    let packageDirectoryRelativePath: String
    let packageRelativePath: String
    let catalogURL: URL
    let packageURL: URL
    let extensionID: String
    let version: String

    func isGenerated(_ path: String) -> Bool {
        path == catalogRelativePath
            || path == packageDirectoryRelativePath
            || path.hasPrefix(packageDirectoryRelativePath + "/")
    }
}

struct ExtensionCatalogUpdate {
    let before: String
    let after: String
    let diff: String
    let latestAdvanced: Bool
}
