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
    func rejectsSemVerPrereleaseNumbersWithLeadingZeros() {
        let catalog = makeCatalog(version: "1.0.0-01", packageURL: URL(string: "1.0.0.zip")!)

        #expect(throws: ExtensionCatalogValidationError.invalidVersion("1.0.0-01")) {
            try ExtensionCatalogValidator.validate(catalog)
        }
    }

    @Test
    func rejectsEmptySemVerPrerelease() {
        let catalog = makeCatalog(version: "1.0.0-", packageURL: URL(string: "1.0.0.zip")!)

        #expect(throws: ExtensionCatalogValidationError.invalidVersion("1.0.0-")) {
            try ExtensionCatalogValidator.validate(catalog)
        }
    }

    @Test
    func rejectsProtocolRelativePackageURLs() {
        let catalog = makeCatalog(version: "1.0.0", packageURL: URL(string: "//other.example/pack.zip")!)

        #expect(throws: ExtensionCatalogValidationError.invalidPackageURL(
            extensionID: "com.example.pack",
            version: "1.0.0"
        )) {
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

    @Test
    func sourceCollectionPreservesOrderAndRejectsDuplicateLocations() throws {
        let first = makeSource(name: "Primary", location: "https://example.com/catalog.json")
        let second = makeSource(name: "Secondary", location: "https://other.example/catalog.json")
        let collection = try ExtensionSourceCollection(sources: [first, second])

        #expect(collection.sources.map(\.id) == [first.id, second.id])
        #expect(throws: ExtensionSourceCollectionError.duplicateSourceLocation) {
            try ExtensionSourceCollection(sources: [
                first,
                makeSource(name: "Duplicate", location: "HTTPS://EXAMPLE.COM/catalog.json/")
            ])
        }
    }

    @Test
    func sourceCollectionRequiresCredentialFreeHTTPSForStaticIndexes() {
        let insecure = makeSource(name: "Insecure", location: "http://example.com/extensions.json")
        let withQuery = makeSource(name: "Query", location: "https://example.com/extensions.json?token=secret")

        #expect(throws: ExtensionSourceCollectionError.invalidSourceLocation(insecure.id)) {
            try ExtensionSourceCollection(sources: [insecure])
        }
        #expect(throws: ExtensionSourceCollectionError.invalidSourceLocation(withQuery.id)) {
            try ExtensionSourceCollection(sources: [withQuery])
        }
    }

    @Test
    func fixtureProviderFeedsValidatedCatalogThroughRegistry() async throws {
        let catalog = makeCatalog(version: "1.2.3", packageURL: URL(string: "1.2.3.zip")!)
        let provider = FixtureSourceProvider(catalog: catalog)
        let registry = try ExtensionSourceProviderRegistry(providers: [provider])
        let source = makeSource(name: "Fixture", location: "https://example.com/extensions.json")
        let resolvedProvider = try registry.provider(for: source)
        let result = try await resolvedProvider.refreshCatalog(for: source, cached: nil)

        try ExtensionCatalogValidator.validate(result.catalog)
        #expect(result.catalog == catalog)
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

    private func makeSource(name: String, location: String) -> ExtensionSource {
        ExtensionSource(
            name: name,
            providerID: .httpsStaticIndex,
            location: URL(string: location)!
        )
    }
}

private struct FixtureSourceProvider: ExtensionSourceProvider {
    let catalog: ExtensionCatalog
    let identifier = ExtensionSourceProviderID.httpsStaticIndex

    func validate(_ source: ExtensionSource) async throws {}

    func refreshCatalog(
        for source: ExtensionSource,
        cached: CachedExtensionCatalog?
    ) async throws -> ExtensionCatalogRefresh {
        ExtensionCatalogRefresh(
            catalog: catalog,
            entityTag: nil,
            lastModified: nil,
            notModified: false
        )
    }

    func download(
        _ package: ExtensionCatalogVersion,
        from source: ExtensionSource,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> DownloadedExtensionPackage {
        DownloadedExtensionPackage(fileURL: destination, byteCount: 0)
    }
}
