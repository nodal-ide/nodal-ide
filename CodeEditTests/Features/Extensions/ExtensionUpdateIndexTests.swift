import Foundation
import Testing
import CodeEditLang
@testable import CodeEdit

@Suite
struct ExtensionUpdateIndexTests {
    @Test
    func offersUpdatesOnlyFromTheRecordedSource() {
        let firstSource = ExtensionInstallFixtures.makeSource(name: "First Registry")
        let secondSource = ExtensionInstallFixtures.makeSource(name: "Second Registry")
        let installed = makeInstalled(
            version: "1.0.0",
            provenance: makeProvenance(source: firstSource, version: "1.0.0")
        )

        let index = ExtensionUpdateIndex(
            installed: [installed],
            catalogs: [
                firstSource.id: makeCatalog(latest: "1.1.0"),
                secondSource.id: makeCatalog(latest: "2.0.0")
            ],
            sources: [firstSource, secondSource],
            appVersion: "0.20.0"
        )

        #expect(index.availableUpdates.count == 1)
        #expect(index.availableUpdates.first?.source.id == firstSource.id)
        #expect(index.availableUpdates.first?.candidate.version == "1.1.0")
        #expect(index.issues.isEmpty)
    }

    @Test
    func ignoresExtensionsWithoutMarketplaceProvenance() {
        let installed = makeInstalled(version: "1.0.0", provenance: nil)
        let index = ExtensionUpdateIndex(
            installed: [installed],
            catalogs: [:],
            sources: [],
            appVersion: "0.20.0"
        )

        #expect(index.trackedCount == 0)
        #expect(index.availableUpdates.isEmpty)
        #expect(index.upToDate.isEmpty)
        #expect(index.issues.isEmpty)
    }

    @Test
    func reportsRemovedDisabledAndUntrustedSources() {
        let removedSource = ExtensionInstallFixtures.makeSource(name: "Removed Registry")
        var disabledSource = ExtensionInstallFixtures.makeSource(name: "Disabled Registry")
        disabledSource.isEnabled = false
        var untrustedSource = ExtensionInstallFixtures.makeSource(name: "Untrusted Registry")
        untrustedSource.isTrusted = false

        let installed = [
            makeInstalled(
                id: "com.example.removed",
                version: "1.0.0",
                provenance: makeProvenance(
                    source: removedSource,
                    extensionID: "com.example.removed",
                    version: "1.0.0"
                )
            ),
            makeInstalled(
                id: "com.example.disabled",
                version: "1.0.0",
                provenance: makeProvenance(
                    source: disabledSource,
                    extensionID: "com.example.disabled",
                    version: "1.0.0"
                )
            ),
            makeInstalled(
                id: "com.example.untrusted",
                version: "1.0.0",
                provenance: makeProvenance(
                    source: untrustedSource,
                    extensionID: "com.example.untrusted",
                    version: "1.0.0"
                )
            )
        ]

        let index = ExtensionUpdateIndex(
            installed: installed,
            catalogs: [:],
            sources: [disabledSource, untrustedSource],
            appVersion: "0.20.0"
        )

        #expect(index.availableUpdates.isEmpty)
        #expect(index.issues.count == 3)
        #expect(index.issues.contains { $0.reason == .sourceMissing })
        #expect(index.issues.contains { $0.reason == .sourceDisabled })
        #expect(index.issues.contains { $0.reason == .sourceUntrusted })
    }

    @Test
    func reportsMissingCatalogAndRemovedCatalogEntry() {
        let missingCatalogSource = ExtensionInstallFixtures.makeSource(name: "Offline Registry")
        let missingEntrySource = ExtensionInstallFixtures.makeSource(name: "Changed Registry")
        let installed = [
            makeInstalled(
                id: "com.example.offline",
                version: "1.0.0",
                provenance: makeProvenance(
                    source: missingCatalogSource,
                    extensionID: "com.example.offline",
                    version: "1.0.0"
                )
            ),
            makeInstalled(
                id: "com.example.removed",
                version: "1.0.0",
                provenance: makeProvenance(
                    source: missingEntrySource,
                    extensionID: "com.example.removed",
                    version: "1.0.0"
                )
            )
        ]

        let index = ExtensionUpdateIndex(
            installed: installed,
            catalogs: [missingEntrySource.id: makeCatalog(latest: "1.1.0")],
            sources: [missingCatalogSource, missingEntrySource],
            appVersion: "0.20.0"
        )

        #expect(index.availableUpdates.isEmpty)
        #expect(index.issues.contains { $0.reason == .catalogUnavailable })
        #expect(index.issues.contains { $0.reason == .notInCatalog })
    }

    @Test
    func ordersSemanticVersionsAndHandlesPrereleases() {
        let source = ExtensionInstallFixtures.makeSource()
        let olderCatalog = makeCatalog(latest: "0.9.0")
        let installed = makeInstalled(
            version: "0.10.0",
            provenance: makeProvenance(source: source, version: "0.10.0")
        )

        let current = ExtensionUpdateIndex(
            installed: [installed],
            catalogs: [source.id: olderCatalog],
            sources: [source],
            appVersion: "0.20.0"
        )
        #expect(current.upToDate.count == 1)
        #expect(current.availableUpdates.isEmpty)

        let prerelease = makeInstalled(
            version: "1.0.0-beta.2",
            provenance: makeProvenance(source: source, version: "1.0.0-beta.2")
        )
        let released = ExtensionUpdateIndex(
            installed: [prerelease],
            catalogs: [source.id: makeCatalog(latest: "1.0.0")],
            sources: [source],
            appVersion: "0.20.0"
        )
        #expect(released.availableUpdates.first?.availableVersion == "1.0.0")
    }

    @Test
    func rejectsUpdatesThatDoNotSupportTheRunningApp() {
        let source = ExtensionInstallFixtures.makeSource()
        let installed = makeInstalled(
            version: "1.0.0",
            provenance: makeProvenance(source: source, version: "1.0.0")
        )

        let index = ExtensionUpdateIndex(
            installed: [installed],
            catalogs: [source.id: makeCatalog(latest: "2.0.0", requirement: ">=0.21.0")],
            sources: [source],
            appVersion: "0.20.0"
        )

        #expect(index.availableUpdates.isEmpty)
        #expect(index.issues.first?.reason == .incompatible(requirement: ">=0.21.0"))
    }

    @Test
    func acceptsCompatibleRequirementAndRejectsMalformedOne() {
        let source = ExtensionInstallFixtures.makeSource()
        let installed = makeInstalled(
            version: "1.0.0",
            provenance: makeProvenance(source: source, version: "1.0.0")
        )

        let compatible = ExtensionUpdateIndex(
            installed: [installed],
            catalogs: [source.id: makeCatalog(latest: "2.0.0", requirement: ">=0.19.0 <0.21.0")],
            sources: [source],
            appVersion: "0.20.0"
        )
        #expect(compatible.availableUpdates.count == 1)

        let malformed = ExtensionUpdateIndex(
            installed: [installed],
            catalogs: [source.id: makeCatalog(latest: "2.0.0", requirement: "not a version")],
            sources: [source],
            appVersion: "0.20.0"
        )
        #expect(malformed.availableUpdates.isEmpty)
        #expect(malformed.issues.first?.reason == .invalidRequirement("not a version"))
    }

    private func makeInstalled(
        id: String = "com.example.demo",
        version: String,
        provenance: ExtensionProvenance?
    ) -> InstalledLanguageExtension {
        let manifest = LanguageExtensionManifest(
            schemaVersion: 2,
            id: id,
            name: "Demo",
            version: version,
            type: "languagePack",
            engines: .init(codeedit: ">=0.1.0")
        )
        return InstalledLanguageExtension(
            id: id,
            name: "Demo",
            version: version,
            root: URL(fileURLWithPath: "/tmp/\(id)", isDirectory: true),
            manifest: manifest,
            scope: .global,
            provenance: provenance
        )
    }

    private func makeProvenance(
        source: ExtensionSource,
        extensionID: String = "com.example.demo",
        version: String
    ) -> ExtensionProvenance {
        ExtensionProvenance(
            source: source,
            extensionID: extensionID,
            version: version,
            integrity: String(repeating: "a", count: 64)
        )
    }

    private func makeCatalog(
        extensionID: String = "com.example.demo",
        latest: String,
        requirement: String? = nil
    ) -> ExtensionCatalog {
        let package = ExtensionCatalogVersion(
            url: URL(string: "https://registry.example/packages/demo-\(latest).zip")!,
            integrity: String(repeating: "a", count: 64),
            publishedAt: nil,
            nodal: requirement
        )
        let entry = ExtensionCatalogEntry(
            name: "Demo",
            description: "Demo extension",
            publisher: "Example",
            url: nil,
            latest: latest,
            versions: [latest: package]
        )
        return ExtensionCatalog(schemaVersion: 1, extensions: [extensionID: entry])
    }
}
