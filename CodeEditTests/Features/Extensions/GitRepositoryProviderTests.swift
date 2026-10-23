@testable import CodeEdit
import CryptoKit
import Foundation
import Testing

@Suite(.serialized)
struct GitRepositoryProviderTests {
    @Test
    func refreshesPinnedTagsCommitsAndDefaultBranch() async throws {
        try await withFixture { fixture in
            let firstPackage = Data("first package".utf8)
            let firstIntegrity = try await fixture.publish(
                version: "1.0.0",
                packagePath: "extensions/com.example.demo/1.0.0/1.0.0.zip",
                packageBytes: firstPackage
            )
            let firstCommit = try await fixture.headSHA()
            try await fixture.tag("v1")

            let secondPackage = Data("second package".utf8)
            let secondIntegrity = try await fixture.publish(
                version: "2.0.0",
                packagePath: "extensions/com.example.demo/2.0.0/2.0.0.zip",
                packageBytes: secondPackage
            )

            let tagSource = fixture.source(revision: "v1")
            let tagCatalog = try await fixture.provider.refreshCatalog(for: tagSource, cached: nil).catalog
            #expect(tagCatalog.extensions["com.example.demo"]?.latest == "1.0.0")
            #expect(tagCatalog.extensions["com.example.demo"]?.versions["1.0.0"]?.integrity == firstIntegrity)

            let shaSource = fixture.source(revision: firstCommit)
            let shaCatalog = try await fixture.provider.refreshCatalog(for: shaSource, cached: nil).catalog
            #expect(shaCatalog.extensions["com.example.demo"]?.latest == "1.0.0")

            let defaultSource = fixture.source(revision: nil)
            let defaultCatalog = try await fixture.provider.refreshCatalog(
                for: defaultSource,
                cached: nil
            ).catalog
            #expect(defaultCatalog.extensions["com.example.demo"]?.latest == "2.0.0")
            #expect(defaultCatalog.extensions["com.example.demo"]?.versions["2.0.0"]?.integrity == secondIntegrity)

            let downloadURL = fixture.root.appending(path: "downloaded.zip")
            let package = try #require(tagCatalog.extensions["com.example.demo"]?.versions["1.0.0"])
            let downloaded = try await fixture.provider.download(
                package,
                from: tagSource,
                to: downloadURL,
                progress: { _, _ in }
            )
            #expect(try Data(contentsOf: downloaded.fileURL) == firstPackage)
        }
    }

    @Test
    func rejectsInvalidGitSourcesAndRevisions() async throws {
        let provider = GitRepositoryProvider(
            cacheDirectory: FileManager.default.temporaryDirectory
                .appending(path: "GitProviderValidation-\(UUID().uuidString)")
        )

        let insecure = ExtensionSource(
            name: "Insecure",
            providerID: .gitRepository,
            location: URL(string: "http://github.com/example/registry")!
        )
        do {
            try await provider.validate(insecure)
            Issue.record("Expected the HTTP Git URL to be rejected.")
        } catch ExtensionSourceProviderError.invalidConfiguration {
            // Expected.
        }

        let ssh = ExtensionSource(
            name: "SSH",
            providerID: .gitRepository,
            location: URL(string: "ssh://git@github.com/example/registry.git")!,
            revision: "release/1.0"
        )
        try await provider.validate(ssh)

        let badRevision = ExtensionSource(
            name: "Bad revision",
            providerID: .gitRepository,
            location: URL(string: "https://github.com/example/registry")!,
            revision: "../main"
        )
        do {
            try await provider.validate(badRevision)
            Issue.record("Expected the invalid revision to be rejected.")
        } catch ExtensionSourceProviderError.invalidConfiguration {
            // Expected.
        }

    }

    @Test
    func rejectsInvalidGitPackagePaths() async {
        let provider = GitRepositoryProvider(
            cacheDirectory: FileManager.default.temporaryDirectory
                .appending(path: "GitProviderValidation-\(UUID().uuidString)")
        )
        let source = ExtensionSource(
            name: "SSH",
            providerID: .gitRepository,
            location: URL(string: "ssh://git@github.com/example/registry.git")!
        )
        for path in ["../outside.zip", "outside.zip?token=secret"] {
            await expectInvalidPackagePath(
                ExtensionCatalogVersion(
                    url: URL(string: path)!,
                    integrity: String(repeating: "a", count: 64),
                    publishedAt: nil,
                    nodal: nil
                ),
                provider: provider,
                source: source
            )
        }
    }

    @Test
    func reportsMissingCatalogAndRequiresRefreshBeforeDownload() async throws {
        try await withFixture { fixture in
            _ = try await fixture.publish(
                version: "1.0.0",
                packagePath: "extensions/com.example.demo/1.0.0/1.0.0.zip",
                packageBytes: Data("first package".utf8)
            )
            let source = fixture.source(revision: nil)
            try await fixture.git(["rm", "extensions.json"], in: fixture.repo)
            try await fixture.git(["commit", "--quiet", "-m", "Remove catalog"], in: fixture.repo)

            do {
                _ = try await fixture.provider.refreshCatalog(for: source, cached: nil)
                Issue.record("Expected a missing catalog error.")
            } catch ExtensionSourceProviderError.invalidResponse {
                // Expected.
            }

            let package = ExtensionCatalogVersion(
                url: URL(string: "extensions/com.example.demo/1.0.0/1.0.0.zip")!,
                integrity: String(repeating: "a", count: 64),
                publishedAt: nil,
                nodal: nil
            )
            do {
                _ = try await fixture.provider.download(
                    package,
                    from: source,
                    to: fixture.root.appending(path: "missing.zip"),
                    progress: { _, _ in }
                )
                Issue.record("Expected a refresh requirement.")
            } catch ExtensionSourceProviderError.transport {
                // Expected.
            }
        }
    }

    @Test
    func verifiesDownloadedDigestAndRemovesMismatchedFiles() async throws {
        try await withFixture { fixture in
            _ = try await fixture.publish(
                version: "1.0.0",
                packagePath: "extensions/com.example.demo/1.0.0/1.0.0.zip",
                packageBytes: Data("first package".utf8)
            )
            let source = fixture.source(revision: nil)
            let catalog = try await fixture.provider.refreshCatalog(for: source, cached: nil).catalog
            var package = try #require(catalog.extensions["com.example.demo"]?.versions["1.0.0"])
            package = ExtensionCatalogVersion(
                url: package.url,
                integrity: String(repeating: "0", count: 64),
                publishedAt: package.publishedAt,
                nodal: package.nodal
            )
            let destination = fixture.root.appending(path: "mismatch.zip")

            do {
                _ = try await fixture.provider.download(
                    package,
                    from: source,
                    to: destination,
                    progress: { _, _ in }
                )
                Issue.record("Expected an integrity mismatch.")
            } catch ExtensionSourceProviderError.integrityMismatch {
                #expect(!FileManager.default.fileExists(atPath: destination.path))
            }
        }
    }

    @Test
    func normalizesSCPStyleRepositoryURLs() throws {
        let url = try #require(GitRepositoryLocation.normalizedURL(from: "git@github.com:nodal-ide/registry.git"))
        #expect(url.absoluteString == "ssh://git@github.com/nodal-ide/registry.git")
        #expect(GitRepositoryLocation.isValid(url))
    }
}

private extension GitRepositoryProviderTests {
    func withFixture(_ body: (GitFixture) async throws -> Void) async throws {
        let fixture = try await GitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await body(fixture)
    }

    func expectInvalidPackagePath(
        _ package: ExtensionCatalogVersion,
        provider: GitRepositoryProvider,
        source: ExtensionSource
    ) async {
        do {
            _ = try await provider.download(
                package,
                from: source,
                to: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                progress: { _, _ in }
            )
            Issue.record("Expected a package path rejection.")
        } catch ExtensionSourceProviderError.invalidConfiguration {
            // Expected.
        } catch {
            Issue.record("Unexpected package path error: \(error)")
        }
    }

}

private struct GitFixture {
    let root: URL
    let repo: URL
    let provider: GitRepositoryProvider
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    init() async throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "GitRepositoryProviderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        repo = root.appending(path: "registry", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        provider = GitRepositoryProvider(cacheDirectory: root.appending(path: "cache"))
        try await git(["init", "-q", "-b", "main"], in: repo)
        try await git(["config", "user.name", "Git Provider Tests"], in: repo)
        try await git(["config", "user.email", "git-provider@example.com"], in: repo)
        try await git(["config", "commit.gpgsign", "false"], in: repo)
        try Data("fixture".utf8).write(to: repo.appending(path: "README.md"))
        try await git(["add", "."], in: repo)
        try await git(["commit", "--quiet", "-m", "Initial fixture"], in: repo)
    }

    func source(revision: String?) -> ExtensionSource {
        ExtensionSource(
            name: "Fixture Git Registry",
            providerID: .gitRepository,
            location: repo,
            revision: revision,
            isTrusted: true
        )
    }

    @discardableResult
    func publish(version: String, packagePath: String, packageBytes: Data) async throws -> String {
        let packageURL = repo.appending(path: packagePath)
        try FileManager.default.createDirectory(
            at: packageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try packageBytes.write(to: packageURL)
        let integrity = SHA256.hash(data: packageBytes).map { String(format: "%02x", $0) }.joined()
        let package = ExtensionCatalogVersion(
            url: URL(string: packagePath)!,
            integrity: integrity,
            publishedAt: nil,
            nodal: nil
        )
        let entry = ExtensionCatalogEntry(
            name: "Demo",
            description: "Fixture extension",
            publisher: "Tests",
            url: nil,
            latest: version,
            versions: [version: package]
        )
        let catalog = ExtensionCatalog(
            schemaVersion: 1,
            extensions: ["com.example.demo": entry]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: repo.appending(path: "extensions.json"))
        try await git(["add", "."], in: repo)
        try await git(["commit", "--quiet", "-m", "Publish \(version)"], in: repo)
        return integrity
    }

    func tag(_ name: String) async throws {
        try await git(["tag", name], in: repo)
    }

    func headSHA() async throws -> String {
        try await git(["rev-parse", "HEAD"], in: repo).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func git(_ arguments: [String], in directory: URL) async throws -> CommandOutput {
        try await CommandRunner().run(
            executable: gitURL,
            arguments: arguments,
            currentDirectory: directory,
            environment: [
                "GIT_AUTHOR_NAME": "Git Provider Tests",
                "GIT_AUTHOR_EMAIL": "git-provider@example.com",
                "GIT_COMMITTER_NAME": "Git Provider Tests",
                "GIT_COMMITTER_EMAIL": "git-provider@example.com",
                "GIT_CONFIG_NOSYSTEM": "1"
            ]
        )
    }
}
