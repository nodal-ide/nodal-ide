//
//  ExtensionRegistryPublishTests.swift
//  CodeEditTests
//

import Foundation
import XCTest
@testable import CodeEdit

extension ExtensionRegistryTests {

    func testPublishCommitsOnlyTheCatalogAndPackage() async throws {
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

        try Data("tracked".utf8).write(to: registry.appending(path: "notes.txt"))
        try await commitAll(in: registry, message: "Add notes")
        try Data("dirty".utf8).write(to: registry.appending(path: "notes.txt"))
        try Data("staged".utf8).write(to: registry.appending(path: "staged.txt"))
        try await git(["add", "staged.txt"], in: registry)

        let preparation = try await service.preparePublish(
            configuration: snapshot.configuration,
            packageAt: pack
        )
        let result = try await service.publish(preparation: preparation, pushAfterCommit: false)

        guard case .committedLocally(let commitSHA) = result.outcome else {
            return XCTFail("Expected a local commit.")
        }
        let files = Set(try await commitFiles(commitSHA, in: registry))
        XCTAssertEqual(files, Set(["extensions.json", "extensions/com.example.demo/1.2.3/1.2.3.zip"]))
        let committedCatalog = try await gitOutput(["show", "\(commitSHA):extensions.json"], in: registry)
        XCTAssertTrue(committedCatalog.contains("1.2.3"))

        let status = try await gitOutput(["status", "--porcelain"], in: registry)
        XCTAssertTrue(status.contains("notes.txt"))
        XCTAssertTrue(status.contains("staged.txt"))
    }

    func testPublishWorksOnNewRegistryWithoutInitialCommit() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let registry = root.appending(path: "registry", directoryHint: .isDirectory)
        let pack = root.appending(path: "Demo.codeext", directoryHint: .isDirectory)
        try writePack(at: pack, id: "com.example.demo", version: "1.0.0")
        let service = makeService(root: root)
        let snapshot = try await service.initialize(
            workingCopy: registry,
            name: "Test Registry",
            cloneURL: nil,
            branch: "main",
            catalogURL: nil
        )
        try await configureIdentity(in: registry)

        let preparation = try await service.preparePublish(
            configuration: snapshot.configuration,
            packageAt: pack
        )
        XCTAssertFalse(preparation.unrelatedChanges.contains { $0.path == "extensions.json" })
        let result = try await service.publish(preparation: preparation, pushAfterCommit: false)

        guard case .committedLocally(let commitSHA) = result.outcome else {
            return XCTFail("Expected a local commit.")
        }
        let files = Set(try await commitFiles(commitSHA, in: registry))
        XCTAssertEqual(files, Set(["extensions.json", "extensions/com.example.demo/1.0.0/1.0.0.zip"]))
    }

    func testPushFailureKeepsCommitAndRetryPushesIt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let registry = root.appending(path: "registry", directoryHint: .isDirectory)
        let pack = root.appending(path: "Demo.codeext", directoryHint: .isDirectory)
        let remote = root.appending(path: "remote.git", directoryHint: .isDirectory)
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

        var configuration = snapshot.configuration
        configuration.remote = "origin"
        _ = try await git(["remote", "add", "origin", remote.path], in: registry)

        let preparation = try await service.preparePublish(
            configuration: configuration,
            packageAt: pack
        )
        let result = try await service.publish(preparation: preparation, pushAfterCommit: true)
        guard case .pushFailed(let commitSHA, _) = result.outcome else {
            return XCTFail("Expected push failure.")
        }
        let head = try await gitOutput(["rev-parse", "HEAD"], in: registry)
        XCTAssertEqual(head, commitSHA)
        let pending = try await service.inspect(configuration: configuration).pendingPush
        XCTAssertEqual(pending?.commitSHA, commitSHA)

        _ = try await git(["init", "--bare", remote.path], in: root)
        let retried = try await service.retryPendingPush(configuration: configuration)
        XCTAssertEqual(retried, commitSHA)
        let snapshotAfterRetry = try await service.inspect(configuration: configuration)
        XCTAssertNil(snapshotAfterRetry.pendingPush)
        let remoteFiles = try await gitOutput(
            ["--git-dir", remote.path, "show", "--name-only", "--pretty=format:", commitSHA],
            in: root
        )
        XCTAssertTrue(remoteFiles.contains("extensions.json"))
    }
}
