import Foundation
import Testing
@testable import CodeEdit

@Suite
struct ExtensionStoreInstallTests {
    @Test
    func installsUpdatesAndPersistsProvenance() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let store = LanguageExtensionStore(extensionsDirectory: directory.appending(path: "Extensions"))
            let source = ExtensionInstallFixtures.makeSource()
            let firstProvenance = ExtensionProvenance(
                source: source,
                extensionID: "com.example.demo",
                version: "1.0.0",
                integrity: String(repeating: "a", count: 64),
                installedAt: Date(timeIntervalSince1970: 1)
            )
            let firstPackage = try ExtensionInstallFixtures.makePackage(
                in: directory,
                version: "1.0.0",
                files: ["README.md": "first"]
            )

            let first = try store.install(
                packageAt: firstPackage,
                provenance: firstProvenance,
                expectedIdentity: .init(extensionID: "com.example.demo", version: "1.0.0")
            )

            #expect(first.version == "1.0.0")
            #expect(first.provenance == firstProvenance)
            #expect(ExtensionProvenance.load(from: first.root) == firstProvenance)
            #expect(try String(contentsOf: first.root.appending(path: "README.md")) == "first")

            let secondProvenance = ExtensionProvenance(
                source: source,
                extensionID: "com.example.demo",
                version: "2.0.0",
                integrity: String(repeating: "b", count: 64),
                installedAt: Date(timeIntervalSince1970: 2)
            )
            let secondPackage = try ExtensionInstallFixtures.makePackage(
                in: directory,
                version: "2.0.0",
                files: ["README.md": "second"]
            )

            let second = try store.install(
                packageAt: secondPackage,
                provenance: secondProvenance,
                expectedIdentity: .init(extensionID: "com.example.demo", version: "2.0.0")
            )

            #expect(second.root.standardizedFileURL.path == first.root.standardizedFileURL.path)
            #expect(second.provenance == secondProvenance)
            #expect(ExtensionProvenance.load(from: second.root) == secondProvenance)
            #expect(try String(contentsOf: second.root.appending(path: "README.md")) == "second")
            #expect(store.globalExtensions().first?.version == "2.0.0")

            try store.remove(second)
            #expect(store.globalExtensions().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: second.root.path))
        }
    }

    @Test
    func failedUpdateKeepsPreviousPackageAndProvenance() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let store = LanguageExtensionStore(extensionsDirectory: directory.appending(path: "Extensions"))
            let source = ExtensionInstallFixtures.makeSource()
            let provenance = ExtensionProvenance(
                source: source,
                extensionID: "com.example.demo",
                version: "1.0.0",
                integrity: String(repeating: "a", count: 64)
            )
            let installed = try store.install(
                packageAt: try ExtensionInstallFixtures.makePackage(in: directory, version: "1.0.0"),
                provenance: provenance,
                expectedIdentity: .init(extensionID: "com.example.demo", version: "1.0.0")
            )

            let wrongVersion = try ExtensionInstallFixtures.makePackage(in: directory, version: "9.9.9")
            #expect(throws: LanguageExtensionInstallError.self) {
                _ = try store.install(
                    packageAt: wrongVersion,
                    provenance: provenance,
                    expectedIdentity: .init(extensionID: "com.example.demo", version: "2.0.0")
                )
            }

            let stillInstalled = try #require(store.globalExtensions().first)
            #expect(stillInstalled.root.standardizedFileURL.path == installed.root.standardizedFileURL.path)
            #expect(stillInstalled.version == "1.0.0")
            #expect(ExtensionProvenance.load(from: installed.root) == provenance)

            let wrongIdentity = try ExtensionInstallFixtures.makePackage(
                in: directory,
                id: "com.example.other",
                version: "2.0.0"
            )
            #expect(throws: LanguageExtensionInstallError.self) {
                _ = try store.install(
                    packageAt: wrongIdentity,
                    provenance: provenance,
                    expectedIdentity: .init(extensionID: "com.example.demo", version: "2.0.0")
                )
            }
            #expect(store.globalExtensions().first?.id == "com.example.demo")
        }
    }

    @Test
    func localReplacementClearsMarketplaceProvenance() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let store = LanguageExtensionStore(extensionsDirectory: directory.appending(path: "Extensions"))
            let source = ExtensionInstallFixtures.makeSource()
            let provenance = ExtensionProvenance(
                source: source,
                extensionID: "com.example.demo",
                version: "1.0.0",
                integrity: String(repeating: "a", count: 64)
            )
            let installed = try store.install(
                packageAt: try ExtensionInstallFixtures.makePackage(in: directory, version: "1.0.0"),
                provenance: provenance
            )
            #expect(installed.provenance != nil)

            let local = try ExtensionInstallFixtures.makePackage(in: directory, version: "1.1.0")
            let replacement = try store.install(fromFolder: local)

            #expect(replacement.provenance == nil)
            #expect(ExtensionProvenance.load(from: replacement.root) == nil)
        }
    }

    @Test
    func discoveryIgnoresMismatchedProvenance() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let extensions = directory.appending(path: "Extensions")
            let root = try ExtensionInstallFixtures.makePackage(in: directory, version: "1.0.0")
            let installedRoot = extensions.appending(path: "com.example.demo")
            try FileManager.default.createDirectory(at: extensions, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: root, to: installedRoot)

            let source = ExtensionInstallFixtures.makeSource()
            let forged = ExtensionProvenance(
                source: source,
                extensionID: "com.example.demo",
                version: "9.0.0",
                integrity: String(repeating: "a", count: 64)
            )
            try forged.write(to: installedRoot)

            let store = LanguageExtensionStore(extensionsDirectory: extensions)
            #expect(store.globalExtensions().first?.provenance == nil)
        }
    }
}
