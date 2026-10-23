//
//  GitRepositoryProvider.swift
//  CodeEdit
//
//  Reads extension catalogs and packages from a cached bare Git repository.
//

import CryptoKit
import Foundation

actor GitRepositoryProvider: ExtensionSourceProvider {
    nonisolated let identifier: ExtensionSourceProviderID = .gitRepository

    private static let maximumCatalogBytes = Int64(HTTPSStaticIndexProvider.maximumCatalogBytes)
    private static let maximumPackageBytes = HTTPSStaticIndexProvider.maximumPackageBytes
    private static let environment = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=20 "
            + "-o ServerAliveInterval=15 -o ServerAliveCountMax=3",
        "LC_ALL": "C"
    ]

    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let runner = CommandRunner()
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    init(
        cacheDirectory: URL = GitRepositoryProvider.defaultCacheDirectory,
        fileManager: FileManager = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
    }

    func validate(_ source: ExtensionSource) async throws {
        guard source.providerID == identifier,
              GitRepositoryLocation.isValid(source.location) else {
            throw ExtensionSourceProviderError.invalidConfiguration(
                "A credential-free HTTPS, SSH, or local Git repository URL is required."
            )
        }
        guard GitRepositoryLocation.isValidRevision(source.revision) else {
            throw ExtensionSourceProviderError.invalidConfiguration(
                "Use a branch, tag, or commit name without spaces or revision operators."
            )
        }
    }

    func refreshCatalog(
        for source: ExtensionSource,
        cached: CachedExtensionCatalog?
    ) async throws -> ExtensionCatalogRefresh {
        do {
            try await validate(source)
            try Task.checkCancellation()
            let repository = try await ensureRepository(for: source)
            let commit = try await fetch(source, in: repository)
            let data = try await readBlob(
                "extensions.json",
                commit: commit,
                in: repository,
                maximumBytes: Self.maximumCatalogBytes
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let catalog = try decoder.decode(ExtensionCatalog.self, from: data)
            try ExtensionCatalogValidator.validate(catalog)
            try writeResolvedCommit(commit, to: repository)
            return ExtensionCatalogRefresh(
                catalog: catalog,
                entityTag: nil,
                lastModified: nil,
                notModified: false
            )
        } catch {
            throw Self.providerError(from: error)
        }
    }

    func download(
        _ package: ExtensionCatalogVersion,
        from source: ExtensionSource,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> DownloadedExtensionPackage {
        do {
            try await validate(source)
            try Task.checkCancellation()
            guard let path = GitRepositoryLocation.packagePath(from: package.url) else {
                throw ExtensionSourceProviderError.invalidConfiguration(
                    "Git sources require repository-relative package paths without traversal."
                )
            }
            let repository = try repositoryURL(for: source)
            guard let commit = try readResolvedCommit(from: repository) else {
                throw ExtensionSourceProviderError.transport(
                    "Refresh this Git source before installing its packages."
                )
            }
            let byteCount = try await blobSize(path, commit: commit, in: repository)
            guard byteCount <= Self.maximumPackageBytes else {
                throw ExtensionSourceProviderError.responseTooLarge
            }
            progress(0, byteCount)
            try await writeBlob(path, commit: commit, in: repository, to: destination)
            let downloaded = try verifyDownload(
                at: destination,
                expectedBytes: byteCount,
                integrity: package.integrity
            )
            progress(byteCount, byteCount)
            return downloaded
        } catch is CancellationError {
            try? fileManager.removeItem(at: destination)
            throw ExtensionSourceProviderError.cancelled
        } catch let error as ExtensionSourceProviderError {
            try? fileManager.removeItem(at: destination)
            throw error
        } catch {
            try? fileManager.removeItem(at: destination)
            throw Self.providerError(from: error)
        }
    }

    func removeCache(for sourceID: ExtensionSourceID) async {
        try? fileManager.removeItem(at: repositoryURL(for: sourceID))
    }

    private static var defaultCacheDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appending(path: "Nodal/ExtensionSourceGit", directoryHint: .isDirectory)
    }

}

private extension GitRepositoryProvider {
    private func repositoryURL(for source: ExtensionSource) throws -> URL {
        try repositoryURL(for: source.id)
    }

    private func repositoryURL(for sourceID: ExtensionSourceID) throws -> URL {
        let url = cacheDirectory.appending(
            path: "\(sourceID.rawValue.uuidString).git",
            directoryHint: .isDirectory
        )
        let repositoryComponents = url.standardizedFileURL.pathComponents
        let cacheComponents = cacheDirectory.standardizedFileURL.pathComponents
        guard repositoryComponents.count == cacheComponents.count + 1,
              repositoryComponents.starts(with: cacheComponents) else {
            throw ExtensionSourceProviderError.invalidConfiguration("Invalid source cache location.")
        }
        return url
    }

    private func ensureRepository(for source: ExtensionSource) async throws -> URL {
        let repository = try repositoryURL(for: source)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: repository.path(percentEncoded: false)) {
            try await runGit(["init", "--bare", repository.path(percentEncoded: false)], in: cacheDirectory)
        }

        let remote = try await runGit(
            ["remote", "get-url", "origin"],
            in: repository,
            acceptedStatuses: [0, 2, 128]
        )
        let location = source.location.absoluteString
        if remote.status == 0 {
            if remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines) != location {
                try await runGit(["remote", "set-url", "origin", location], in: repository)
            }
        } else {
            try await runGit(["remote", "add", "origin", location], in: repository)
        }
        return repository
    }

    private func fetch(_ source: ExtensionSource, in repository: URL) async throws -> String {
        let revision = GitRepositoryLocation.normalizedRevision(source.revision) ?? "HEAD"
        try await runGit(
            [
                "fetch", "--quiet", "--force", "--no-tags", "--depth=1",
                "--no-recurse-submodules", "origin", revision
            ],
            in: repository
        )
        let resolved = try await runGit(["rev-parse", "--verify", "FETCH_HEAD^{commit}"], in: repository)
        let commit = resolved.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isCommitSHA(commit) else {
            throw ExtensionSourceProviderError.invalidResponse
        }
        return commit
    }

    private func readBlob(
        _ path: String,
        commit: String,
        in repository: URL,
        maximumBytes: Int64
    ) async throws -> Data {
        let size = try await blobSize(path, commit: commit, in: repository)
        guard size <= maximumBytes else { throw ExtensionSourceProviderError.responseTooLarge }
        let output = try await runGit(["cat-file", "blob", "\(commit):\(path)"], in: repository)
        guard let data = output.stdout.data(using: .utf8), data.count == size else {
            throw ExtensionSourceProviderError.invalidResponse
        }
        return data
    }

    private func blobSize(_ path: String, commit: String, in repository: URL) async throws -> Int64 {
        let spec = "\(commit):\(path)"
        let type = try await runGit(["cat-file", "-t", spec], in: repository, acceptedStatuses: [0, 128])
        guard type.status == 0,
              type.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "blob" else {
            throw ExtensionSourceProviderError.invalidResponse
        }
        let size = try await runGit(["cat-file", "-s", spec], in: repository, acceptedStatuses: [0, 128])
        guard size.status == 0,
              let byteCount = Int64(size.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
              byteCount >= 0 else {
            throw ExtensionSourceProviderError.invalidResponse
        }
        return byteCount
    }

    private func writeBlob(
        _ path: String,
        commit: String,
        in repository: URL,
        to destination: URL
    ) async throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await runGit(
            ["cat-file", "blob", "\(commit):\(path)"],
            in: repository,
            stdoutDestination: destination
        )
    }

    private func verifyDownload(
        at destination: URL,
        expectedBytes: Int64,
        integrity: String
    ) throws -> DownloadedExtensionPackage {
        let attributes = try fileManager.attributesOfItem(atPath: destination.path(percentEncoded: false))
        guard let size = (attributes[.size] as? NSNumber)?.int64Value,
              size == expectedBytes,
              size > 0 else {
            throw ExtensionSourceProviderError.invalidResponse
        }
        let digest = try fileSHA256(destination)
        guard digest == integrity else { throw ExtensionSourceProviderError.integrityMismatch }
        return DownloadedExtensionPackage(fileURL: destination, byteCount: size)
    }

    private func fileSHA256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func writeResolvedCommit(_ commit: String, to repository: URL) throws {
        try Data(commit.utf8).write(
            to: repository.appending(path: "NODAL_RESOLVED_COMMIT"),
            options: .atomic
        )
    }

    private func readResolvedCommit(from repository: URL) throws -> String? {
        let url = repository.appending(path: "NODAL_RESOLVED_COMMIT")
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let value = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.isCommitSHA(value) ? value : nil
    }

    private static func isCommitSHA(_ value: String) -> Bool {
        (40...64).contains(value.utf8.count)
            && value.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0)
            }
    }

    @discardableResult
    private func runGit(
        _ arguments: [String],
        in directory: URL,
        stdoutDestination: URL? = nil,
        acceptedStatuses: Set<Int32> = [0]
    ) async throws -> CommandOutput {
        try await runner.run(
            executable: gitURL,
            arguments: arguments,
            currentDirectory: directory,
            environment: Self.environment,
            stdoutDestination: stdoutDestination,
            acceptedStatuses: acceptedStatuses
        )
    }

    private static func providerError(from error: Error) -> ExtensionSourceProviderError {
        if error is CancellationError { return .cancelled }
        if let error = error as? ExtensionSourceProviderError { return error }
        guard case let CommandRunnerError.failed(_, _, message) = error else {
            return .transport(error.localizedDescription)
        }
        let detail = message
            .split(whereSeparator: \.isNewline)
            .prefix(3)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = detail.lowercased()
        if lowercase.contains("permission denied")
            || lowercase.contains("authentication failed")
            || lowercase.contains("could not read username")
            || lowercase.contains("terminal prompts disabled") {
            return .transport(
                "Git authentication failed. Configure SSH or Git credentials for this repository."
            )
        }
        if lowercase.contains("couldn't find remote ref")
            || lowercase.contains("not our ref")
            || lowercase.contains("unadvertised object") {
            return .invalidConfiguration("The Git revision was not found in the repository.")
        }
        return .transport(detail.isEmpty ? "The Git repository operation failed." : detail)
    }
}
