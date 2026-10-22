@testable import CodeEdit
import Foundation
import Testing

@Suite
struct ExtensionCatalogModelsTests {
    @Test
    func acceptsStrictSemVerAndRelativeHTTPSPackageURL() throws {
        let catalog = makeCatalog(version: "1.2.3-rc.1+build.4", packageURL: URL(string: "packs/1.2.3.zip")!)

        try ExtensionCatalogValidator.validate(catalog)
    }

    @Test
    func rejectsUnsupportedSchemaVersions() {
        let catalog = ExtensionCatalog(schemaVersion: 2, extensions: [:])

        #expect(throws: ExtensionCatalogValidationError.unsupportedSchemaVersion(2)) {
            try ExtensionCatalogValidator.validate(catalog)
        }
    }

    @Test
    func rejectsLatestVersionMissingFromVersionMap() {
        let entry = ExtensionCatalogEntry(
            name: "Example",
            description: "Test package",
            publisher: "Tests",
            url: nil,
            latest: "1.0.0",
            versions: [:]
        )
        let catalog = ExtensionCatalog(schemaVersion: 1, extensions: ["com.example.pack": entry])

        #expect(throws: ExtensionCatalogValidationError.missingLatestVersion("com.example.pack")) {
            try ExtensionCatalogValidator.validate(catalog)
        }
    }

    @Test
    func candidatesFromDifferentSourcesHaveDifferentIdentity() {
        let firstSource = ExtensionSourceID()
        let secondSource = ExtensionSourceID()
        let entry = ExtensionCatalogEntry(
            name: "Example",
            description: "Test package",
            publisher: "Tests",
            url: nil,
            latest: "1.0.0",
            versions: [:]
        )
        let package = ExtensionCatalogVersion(
            url: URL(string: "packs/1.0.0.zip")!,
            integrity: String(repeating: "a", count: 64),
            publishedAt: nil,
            nodal: nil
        )
        let first = ExtensionCatalogCandidate(
            sourceID: firstSource,
            extensionID: "com.example.pack",
            version: "1.0.0",
            entry: entry,
            package: package
        )
        let second = ExtensionCatalogCandidate(
            sourceID: secondSource,
            extensionID: "com.example.pack",
            version: "1.0.0",
            entry: entry,
            package: package
        )

        #expect(first.id != second.id)
    }

    private func makeCatalog(version: String, packageURL: URL) -> ExtensionCatalog {
        let package = ExtensionCatalogVersion(
            url: packageURL,
            integrity: String(repeating: "0", count: 64),
            publishedAt: nil,
            nodal: nil
        )
        let entry = ExtensionCatalogEntry(
            name: "Example",
            description: "Test package",
            publisher: "Tests",
            url: nil,
            latest: version,
            versions: [version: package]
        )
        return ExtensionCatalog(schemaVersion: 1, extensions: ["com.example.pack": entry])
    }
}
