//
//  ExtensionRegistryTests.swift
//  CodeEditTests
//

import Foundation
import XCTest
@testable import CodeEdit

final class ExtensionRegistryTests: XCTestCase {
    let fileManager = FileManager.default
    let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    override func setUp() {
        continueAfterFailure = false
    }

    func testInitializeCreatesLocalRegistry() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let registry = root.appending(path: "registry", directoryHint: .isDirectory)
        let service = makeService(root: root)

        let snapshot = try await service.initialize(
            workingCopy: registry,
            name: "Test Registry",
            cloneURL: nil,
            branch: "main",
            catalogURL: nil
        )

        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertTrue(snapshot.catalogExists)
        XCTAssertEqual(snapshot.extensionCount, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: registry.appending(path: "README.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: registry.appending(path: ".gitignore").path))
        XCTAssertTrue(fileManager.fileExists(atPath: registry.appending(path: ".git").path))
        XCTAssertTrue(snapshot.changes.contains { $0.path == "extensions.json" })
    }

    func testPrepareRejectsExistingVersion() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let registry = root.appending(path: "registry", directoryHint: .isDirectory)
        let pack = root.appending(path: "Demo.codeext", directoryHint: .isDirectory)
        try writePack(at: pack, id: "com.example.demo", version: "1.2.3")
        let service = makeService(root: root)
        let snapshot = try await service.initialize(
            workingCopy: registry,
            name: "Test Registry",
            cloneURL: nil,
            branch: "main",
            catalogURL: nil
        )
        try await configureIdentity(in: registry)
        try await commitAll(in: registry, message: "Initial registry")

        let preparation = try await service.preparePublish(
            configuration: snapshot.configuration,
            packageAt: pack
        )
        _ = try await service.publish(preparation: preparation, pushAfterCommit: false)

        do {
            _ = try await service.preparePublish(
                configuration: snapshot.configuration,
                packageAt: pack
            )
            XCTFail("Expected duplicate version rejection.")
        } catch let error as ExtensionRegistryError {
            guard case .duplicateVersion = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPrepareRejectsDirtyCatalog() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let registry = root.appending(path: "registry", directoryHint: .isDirectory)
        let pack = root.appending(path: "Demo.codeext", directoryHint: .isDirectory)
        try writePack(at: pack, id: "com.example.demo", version: "1.2.3")
        let service = makeService(root: root)
        let snapshot = try await service.initialize(
            workingCopy: registry,
            name: "Test Registry",
            cloneURL: nil,
            branch: "main",
            catalogURL: nil
        )
        try await configureIdentity(in: registry)
        try await commitAll(in: registry, message: "Initial registry")
        let catalogURL = registry.appending(path: "extensions.json")
        var catalogData = try Data(contentsOf: catalogURL)
        catalogData.append(Data(" ".utf8))
        try catalogData.write(to: catalogURL)

        do {
            _ = try await service.preparePublish(
                configuration: snapshot.configuration,
                packageAt: pack
            )
            XCTFail("Expected a dirty catalog rejection.")
        } catch let error as ExtensionRegistryError {
            guard case .dirtyPaths = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testInitializeClonesExistingRegistry() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let origin = root.appending(path: "origin.git", directoryHint: .isDirectory)
        let seed = root.appending(path: "seed", directoryHint: .isDirectory)
        let destination = root.appending(path: "clone", directoryHint: .isDirectory)

        _ = try await git(["init", "--bare", "-b", "main", origin.path], in: root)
        try fileManager.createDirectory(at: seed, withIntermediateDirectories: true)
        _ = try await git(["init", "-b", "main"], in: seed)
        try await configureIdentity(in: seed)
        try Data("{\"schemaVersion\":1,\"extensions\":{}}\n".utf8)
            .write(to: seed.appending(path: "extensions.json"))
        try await commitAll(in: seed, message: "Initial registry")
        _ = try await git(["remote", "add", "origin", origin.path], in: seed)
        _ = try await git(["push", "origin", "main"], in: seed)

        let snapshot = try await makeService(root: root).initialize(
            workingCopy: destination,
            name: "Cloned Registry",
            cloneURL: origin.path,
            branch: "main",
            catalogURL: nil
        )

        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertTrue(snapshot.catalogExists)
        XCTAssertNotNil(snapshot.remoteURL)
        XCTAssertTrue(fileManager.fileExists(atPath: destination.appending(path: "extensions.json").path))
        XCTAssertEqual(snapshot.configuration.remote, "origin")
    }

    // MARK: - Helpers

    func makeService(root: URL) -> ExtensionRegistryService {
        ExtensionRegistryService(
            journalDirectory: root.appending(path: "journals", directoryHint: .isDirectory)
        )
    }

    func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appending(path: "ExtensionRegistryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func writePack(at root: URL, id: String, version: String) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "schemaVersion": 2,
            "id": id,
            "name": "Demo",
            "version": version,
            "description": "A demo language extension.",
            "author": "Acme",
            "url": "https://example.com",
            "engines": ["codeedit": ">=0.19.0"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appending(path: "extension.json"))
        try Data("demo language\n".utf8).write(to: root.appending(path: "README.md"))
    }

    func configureIdentity(in root: URL) async throws {
        _ = try await git(["config", "user.name", "Registry Tests"], in: root)
        _ = try await git(["config", "user.email", "registry@example.com"], in: root)
        _ = try await git(["config", "commit.gpgsign", "false"], in: root)
    }

    func commitAll(in root: URL, message: String) async throws {
        _ = try await git(["add", "."], in: root)
        _ = try await git(["commit", "--quiet", "-m", message], in: root)
    }

    @discardableResult
    func git(_ arguments: [String], in directory: URL) async throws -> CommandOutput {
        try await CommandRunner().run(
            executable: gitURL,
            arguments: arguments,
            currentDirectory: directory,
            environment: [
                "GIT_AUTHOR_NAME": "Registry Tests",
                "GIT_AUTHOR_EMAIL": "registry@example.com",
                "GIT_COMMITTER_NAME": "Registry Tests",
                "GIT_COMMITTER_EMAIL": "registry@example.com",
                "GIT_CONFIG_NOSYSTEM": "1"
            ]
        )
    }

    func gitOutput(_ arguments: [String], in directory: URL) async throws -> String {
        try await git(arguments, in: directory).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func commitFiles(_ sha: String, in directory: URL) async throws -> [String] {
        let output = try await git(
            ["show", "--pretty=format:", "--name-only", sha],
            in: directory
        )
        return output.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
