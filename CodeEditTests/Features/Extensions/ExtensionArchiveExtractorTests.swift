import Foundation
import Testing
@testable import CodeEdit

@Suite
struct ExtensionArchiveExtractorTests {
    @Test
    func extractsSinglePackageRoot() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let archive = directory.appending(path: "demo.zip")
            try ExtensionInstallFixtures.makeArchive([
                .directory("demo/"),
                .file("demo/extension.json", try ExtensionInstallFixtures.manifestJSON()),
                .file("demo/README.md", "Hello")
            ], at: archive)

            let root = try ExtensionArchiveExtractor().extract(
                archiveAt: archive,
                to: directory.appending(path: "contents")
            )

            #expect(root.lastPathComponent == "demo")
            #expect(try String(contentsOf: root.appending(path: "README.md")) == "Hello")
        }
    }

    @Test
    func rejectsTraversalAndAbsolutePaths() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            for (index, path) in ["../escape.txt", "/absolute.txt", "demo/../../escape.txt"].enumerated() {
                let archive = directory.appending(path: "bad-\(index).zip")
                try ExtensionInstallFixtures.makeArchive([
                    .file(path, "nope")
                ], at: archive)
                #expect(throws: ExtensionArchiveError.self) {
                    _ = try ExtensionArchiveExtractor().extract(
                        archiveAt: archive,
                        to: directory.appending(path: "contents-\(index)")
                    )
                }
            }
        }
    }

    @Test
    func rejectsSymbolicLinks() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let archive = directory.appending(path: "symlink.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/extension.json", try ExtensionInstallFixtures.manifestJSON()),
                .symlink("demo/link", target: "../../etc/passwd")
            ], at: archive)

            #expect(throws: ExtensionArchiveError.self) {
                _ = try ExtensionArchiveExtractor().extract(
                    archiveAt: archive,
                    to: directory.appending(path: "contents")
                )
            }
        }
    }

    @Test
    func rejectsDuplicateAndCaseCollidingPaths() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            for (index, paths) in [
                ["demo/extension.json", "demo/extension.json"],
                ["demo/extension.json", "demo/Extension.json"]
            ].enumerated() {
                let archive = directory.appending(path: "duplicate-\(index).zip")
                try ExtensionInstallFixtures.makeArchive(paths.map { .file($0, "{}") }, at: archive)
                #expect(throws: ExtensionArchiveError.self) {
                    _ = try ExtensionArchiveExtractor().extract(
                        archiveAt: archive,
                        to: directory.appending(path: "contents-\(index)")
                    )
                }
            }
        }
    }

    @Test
    func enforcesEntryAndExpandedSizeLimits() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let archive = directory.appending(path: "large.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/one", "12345"),
                .file("demo/two", "12345")
            ], at: archive)
            let extractor = ExtensionArchiveExtractor(
                maximumEntryBytes: 4,
                maximumExpandedBytes: 100
            )
            #expect(throws: ExtensionArchiveError.self) {
                _ = try extractor.extract(archiveAt: archive, to: directory.appending(path: "one"))
            }

            let expandedExtractor = ExtensionArchiveExtractor(
                maximumEntryBytes: 100,
                maximumExpandedBytes: 9
            )
            #expect(throws: ExtensionArchiveError.self) {
                _ = try expandedExtractor.extract(archiveAt: archive, to: directory.appending(path: "two"))
            }
        }
    }

    @Test
    func enforcesEntryCountLimit() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let archive = directory.appending(path: "many.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/one", "1"),
                .file("demo/two", "2")
            ], at: archive)
            let extractor = ExtensionArchiveExtractor(maximumEntries: 1)
            #expect(throws: ExtensionArchiveError.self) {
                _ = try extractor.extract(archiveAt: archive, to: directory.appending(path: "contents"))
            }
        }
    }

    @Test
    func rejectsArchiveWithoutSingleManifest() throws {
        try ExtensionInstallFixtures.withTempDirectory { directory in
            let archive = directory.appending(path: "missing.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/README.md", "No manifest")
            ], at: archive)
            #expect(throws: ExtensionArchiveError.self) {
                _ = try ExtensionArchiveExtractor().extract(
                    archiveAt: archive,
                    to: directory.appending(path: "contents")
                )
            }
        }
    }
}
