//
//  ExtensionRegistryPackageTests.swift
//  CodeEditTests
//

import Foundation
import XCTest
@testable import CodeEdit

extension ExtensionRegistryTests {
    func testPackageBuilderIsReproducibleAndExcludesRepositoryFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let pack = root.appending(path: "Demo.codeext", directoryHint: .isDirectory)
        try writePack(at: pack, id: "com.example.demo", version: "1.2.3")
        try fileManager.createDirectory(
            at: pack.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data("ignored".utf8).write(to: pack.appending(path: ".git/HEAD"))
        try Data("ignored".utf8).write(to: pack.appending(path: ".DS_Store"))

        let builder = ExtensionPackageBuilder()
        let first = try await builder.build(packageAt: pack)
        let second = try await builder.build(packageAt: pack)
        defer {
            first.removeTemporaryFiles()
            second.removeTemporaryFiles()
        }

        XCTAssertEqual(first.integrity, second.integrity)
        XCTAssertEqual(first.byteCount, second.byteCount)
        XCTAssertEqual(first.manifest.id, "com.example.demo")
        XCTAssertEqual(first.manifest.version, "1.2.3")
        XCTAssertEqual(first.integrity.count, 64)

        let extracted = root.appending(path: "Extracted", directoryHint: .isDirectory)
        _ = try ExtensionArchiveExtractor().extract(archiveAt: first.archiveURL, to: extracted)
        XCTAssertFalse(fileManager.fileExists(atPath: extracted.appending(path: ".git").path))
        XCTAssertFalse(fileManager.fileExists(atPath: extracted.appending(path: ".DS_Store").path))
    }

    func testCatalogUpdatePreservesUnknownFieldsAndLatest() throws {
        let fixture = try makeCatalogFixture()
        let older = try fixture.document.addingRelease(
            makeRelease(version: "1.5.0"),
            packageURL: "extensions/com.example.demo/1.5.0/1.5.0.zip",
            integrity: fixture.integrity,
            publishedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertFalse(older.latestAdvanced)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: older.data) as? [String: Any]
        )
        XCTAssertEqual(object["x-registry-note"] as? String, "keep")
        let extensions = try XCTUnwrap(object["extensions"] as? [String: Any])
        let entry = try XCTUnwrap(extensions["com.example.demo"] as? [String: Any])
        XCTAssertEqual(entry["x-entry-note"] as? String, "keep")
        XCTAssertEqual(entry["latest"] as? String, "2.0.0")
    }

    func testCatalogUpdateAdvancesLatest() throws {
        let fixture = try makeCatalogFixture()
        let older = try fixture.document.addingRelease(
            makeRelease(version: "1.5.0"),
            packageURL: "extensions/com.example.demo/1.5.0/1.5.0.zip",
            integrity: fixture.integrity,
            publishedAt: Date(timeIntervalSince1970: 0)
        )
        let newerDocument = try ExtensionRegistryCatalogDocument(data: older.data)
        let newer = try newerDocument.addingRelease(
            makeRelease(version: "2.1.0"),
            packageURL: "extensions/com.example.demo/2.1.0/2.1.0.zip",
            integrity: fixture.integrity,
            publishedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(newer.latestAdvanced)
        let text = String(bytes: newer.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"latest\" : \"2.1.0\""))
    }

    private func makeCatalogFixture() throws -> (
        document: ExtensionRegistryCatalogDocument,
        integrity: String
    ) {
        let integrity = String(repeating: "a", count: 64)
        let existing = """
        {
          "schemaVersion": 1,
          "x-registry-note": "keep",
          "extensions": {
            "com.example.demo": {
              "name": "Demo",
              "description": "Demo extension",
              "publisher": "Acme",
              "url": "https://example.com",
              "latest": "2.0.0",
              "x-entry-note": "keep",
              "versions": {
                "2.0.0": {
                  "url": "extensions/com.example.demo/2.0.0/2.0.0.zip",
                  "integrity": "\(integrity)",
                  "publishedAt": "2026-01-01T00:00:00Z"
                }
              }
            }
          }
        }
        """
        return (try ExtensionRegistryCatalogDocument(data: Data(existing.utf8)), integrity)
    }

    private func makeRelease(version: String) throws -> ExtensionRegistryRelease {
        try ExtensionRegistryRelease(manifest: ExtensionManifestSummary(
            id: "com.example.demo",
            name: "Demo",
            version: version,
            description: "Demo extension",
            author: "Acme",
            url: "https://example.com"
        ))
    }
}
