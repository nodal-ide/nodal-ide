//
//  ExtensionRegistryService+Files.swift
//  CodeEdit
//
//  Registry layout, path containment, diffs, and the pending-push journal.
//

import CryptoKit
import Foundation

extension ExtensionRegistryService {
    func createInitialFilesIfNeeded(in root: URL, name: String) throws {
        let fileManager = FileManager.default
        let catalogURL = root.appending(path: ExtensionRegistryCatalogDocument.catalogFileName)
        if !fileManager.fileExists(atPath: catalogURL.path(percentEncoded: false)) {
            try ExtensionRegistryCatalogDocument.emptyCatalogData().write(to: catalogURL, options: [.atomic])
        }

        let readmeURL = root.appending(path: "README.md")
        if !fileManager.fileExists(atPath: readmeURL.path(percentEncoded: false)) {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let registryName = trimmedName.isEmpty ? root.lastPathComponent : trimmedName
            let readme = """
            # \(registryName)

            A Nodal IDE extension registry.

            ## Layout

            - `extensions.json` — the catalog served to Nodal IDE.
            - `extensions/<id>/<version>/<version>.zip` — immutable release archives.

            Published versions must not be replaced. Publish a new version instead.

            ## Hosting

            Serve this repository over HTTPS. Register the hosted `extensions.json` URL in
            Nodal IDE under Settings → Extensions → Sources.

            ## Publishing

            In Nodal IDE, open Extensions → Sources and choose **Package & Publish Extension…**.
            The editor validates the package, builds a reproducible ZIP, updates the catalog,
            shows the exact diff, and commits only those files.

            """
            try Data(readme.utf8).write(to: readmeURL, options: [.atomic])
        }

        let ignoreURL = root.appending(path: ".gitignore")
        if !fileManager.fileExists(atPath: ignoreURL.path(percentEncoded: false)) {
            try Data(".DS_Store\n*.tmp\n".utf8).write(to: ignoreURL, options: [.atomic])
        }
    }

    func prepareForClone(at target: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: target.path(percentEncoded: false), isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ExtensionRegistryError.invalidConfiguration(
                    "Choose an empty folder for the registry clone."
                )
            }
            let contents = try fileManager.contentsOfDirectory(atPath: target.path(percentEncoded: false))
            guard contents.isEmpty else {
                throw ExtensionRegistryError.invalidConfiguration(
                    "Choose an empty folder for the registry clone."
                )
            }
        }
    }

    func checkOutOrCreate(branch: String, in root: URL) async throws {
        guard !branch.isEmpty else { return }
        let current = try await git.branch(in: root)
        guard current != branch else { return }

        let exists = try await git.run(
            ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            in: root,
            accepted: [0, 1]
        )
        if exists.status == 0 {
            _ = try await git.run(["checkout", "--quiet", branch], in: root)
        } else {
            _ = try await git.run(["checkout", "--quiet", "-b", branch], in: root)
        }
    }

    func containedURL(for relativePath: String, in root: URL) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains(".."), !relativePath.isEmpty else {
            throw ExtensionRegistryError.unsafePath(relativePath)
        }
        let candidate = root.appending(path: relativePath).standardizedFileURL
        var rootPath = root.standardizedFileURL.path(percentEncoded: false)
        if rootPath.count > 1, rootPath.hasSuffix("/") {
            rootPath.removeLast()
        }
        let candidatePath = candidate.path(percentEncoded: false)
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw ExtensionRegistryError.unsafePath(relativePath)
        }
        return candidate
    }

    func catalogDiff(before: String, after: String, in directory: URL) async throws -> String {
        let beforeURL = directory.appending(path: "extensions.json.before")
        let afterURL = directory.appending(path: "extensions.json.after")
        try Data(before.utf8).write(to: beforeURL, options: [.atomic])
        try Data(after.utf8).write(to: afterURL, options: [.atomic])
        let output = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/diff"),
            arguments: [
                "-u",
                "--label", "extensions.json (before)",
                "--label", "extensions.json (after)",
                beforeURL.path(percentEncoded: false),
                afterURL.path(percentEncoded: false)
            ],
            acceptedStatuses: [0, 1]
        )
        return output.stdout
    }

    func fileSHA256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func loadJournal(for repositoryRoot: URL) throws -> ExtensionPublishJournal? {
        let url = journalURL(for: repositoryRoot)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExtensionPublishJournal.self, from: Data(contentsOf: url))
    }

    func saveJournal(_ journal: ExtensionPublishJournal) throws {
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(
            to: journalURL(for: journal.repositoryRootPath),
            options: [.atomic]
        )
    }

    func removeJournal(for repositoryRoot: URL) throws {
        let url = journalURL(for: repositoryRoot)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func journalURL(for repositoryRoot: URL) -> URL {
        let path = repositoryRoot.path(percentEncoded: false)
        let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return journalDirectory.appending(path: "\(key).json")
    }

    private func journalURL(for repositoryRootPath: String) -> URL {
        journalURL(for: URL(filePath: repositoryRootPath, directoryHint: .isDirectory))
    }

    func configurationRemote(
        configuration: ExtensionRegistryConfiguration,
        snapshot: ExtensionRegistrySnapshot
    ) async throws -> String? {
        let configured = configuration.remote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !configured.isEmpty {
            guard try await git.remoteURL(in: snapshot.repositoryRoot, remote: configured) != nil else {
                return nil
            }
            return configured
        }
        return snapshot.remoteURL == nil ? nil : "origin"
    }
}

enum ExtensionRegistryLocations {
    static func inferCatalogURL(remoteURL: String?, branch: String) -> URL? {
        guard let remoteURL, let slug = repositorySlug(from: remoteURL) else { return nil }
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = trimmedBranch.isEmpty ? "main" : trimmedBranch
        return URL(string: "https://raw.githubusercontent.com/\(slug)/refs/heads/\(branch)/extensions.json")
    }

    static func repositorySlug(from remoteURL: String) -> String? {
        var value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if let url = URL(string: value), url.host?.lowercased() == "github.com" {
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            return nil
        }
        if value.hasSuffix(".git") {
            value.removeLast(4)
        }
        let components = value.split(separator: "/")
        guard components.count == 2 else { return nil }
        return components.joined(separator: "/")
    }
}
