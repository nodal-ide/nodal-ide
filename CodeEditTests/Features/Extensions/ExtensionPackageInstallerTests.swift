import Foundation
import Testing
@testable import CodeEdit

@Suite
struct ExtensionPackageInstallerTests {
    @Test
    func installsCatalogPackageAndRecordsProvenance() async throws {
        try await ExtensionInstallFixtures.withTempDirectory { directory in
            let source = ExtensionInstallFixtures.makeSource()
            let candidate = ExtensionInstallFixtures.makeCandidate(source: source)
            let archive = directory.appending(path: "demo.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/extension.json", try ExtensionInstallFixtures.manifestJSON()),
                .file("demo/README.md", "marketplace")
            ], at: archive)
            let provider = LocalPackageProvider(archiveURL: archive)
            let store = LanguageExtensionStore(extensionsDirectory: directory.appending(path: "Extensions"))
            let installer = try makeInstaller(store: store, providers: [provider])
            let recorder = ProgressRecorder()

            let installed = try await installer.install(
                candidate: candidate,
                from: source,
                progress: { recorder.append($0) }
            )

            #expect(installed.id == candidate.extensionID)
            #expect(installed.version == candidate.version)
            #expect(installed.provenance?.sourceID == source.id)
            #expect(installed.provenance?.version == candidate.version)
            #expect(installed.provenance?.integrity == candidate.package.integrity)
            #expect(try String(contentsOf: installed.root.appending(path: "README.md")) == "marketplace")
            #expect(await provider.downloadCount == 1)

            await MainActor.run {}
            let phases = recorder.phases
            #expect(phases.contains(.preparing))
            #expect(phases.contains(.downloading))
            #expect(phases.contains(.extracting))
            #expect(phases.contains(.validating))
            #expect(phases.contains(.installing))
            #expect(phases.contains(.finished))
        }
    }

    @Test
    func refusesUntrustedOrMismatchedSourcesBeforeDownloading() async throws {
        try await ExtensionInstallFixtures.withTempDirectory { directory in
            let archive = directory.appending(path: "demo.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/extension.json", try ExtensionInstallFixtures.manifestJSON())
            ], at: archive)
            let provider = LocalPackageProvider(archiveURL: archive)
            let store = LanguageExtensionStore(extensionsDirectory: directory.appending(path: "Extensions"))
            let installer = try makeInstaller(store: store, providers: [provider])

            let untrusted = ExtensionInstallFixtures.makeSource(trusted: false)
            let untrustedCandidate = ExtensionInstallFixtures.makeCandidate(source: untrusted)
            await #expect(throws: ExtensionInstallationError.sourceUntrusted) {
                _ = try await installer.install(
                    candidate: untrustedCandidate,
                    from: untrusted,
                    progress: { _ in }
                )
            }

            let trusted = ExtensionInstallFixtures.makeSource()
            let otherSource = ExtensionInstallFixtures.makeSource()
            let otherCandidate = ExtensionInstallFixtures.makeCandidate(source: otherSource)
            await #expect(throws: ExtensionInstallationError.sourceMismatch) {
                _ = try await installer.install(
                    candidate: otherCandidate,
                    from: trusted,
                    progress: { _ in }
                )
            }
            #expect(await provider.downloadCount == 0)
        }
    }

    @Test
    func failedInstallerUpdateKeepsPreviousPackage() async throws {
        try await ExtensionInstallFixtures.withTempDirectory { directory in
            let source = ExtensionInstallFixtures.makeSource()
            let store = LanguageExtensionStore(extensionsDirectory: directory.appending(path: "Extensions"))
            let firstArchive = directory.appending(path: "first.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/extension.json", try ExtensionInstallFixtures.manifestJSON(version: "1.0.0")),
                .file("demo/README.md", "first")
            ], at: firstArchive)
            let firstInstaller = try makeInstaller(
                store: store,
                providers: [LocalPackageProvider(archiveURL: firstArchive)]
            )
            let installed = try await firstInstaller.install(
                candidate: ExtensionInstallFixtures.makeCandidate(source: source, version: "1.0.0"),
                from: source,
                progress: { _ in }
            )

            let badArchive = directory.appending(path: "bad.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/extension.json", try ExtensionInstallFixtures.manifestJSON(version: "9.9.9"))
            ], at: badArchive)
            let badInstaller = try makeInstaller(
                store: store,
                providers: [LocalPackageProvider(archiveURL: badArchive)]
            )
            await #expect(throws: LanguageExtensionInstallError.self) {
                _ = try await badInstaller.install(
                    candidate: ExtensionInstallFixtures.makeCandidate(source: source, version: "2.0.0"),
                    from: source,
                    progress: { _ in }
                )
            }

            let stillInstalled = try #require(store.globalExtensions().first)
            #expect(stillInstalled.version == "1.0.0")
            #expect(stillInstalled.root.standardizedFileURL.path == installed.root.standardizedFileURL.path)
            #expect(try String(contentsOf: stillInstalled.root.appending(path: "README.md")) == "first")
        }
    }

    @Test
    func cancellingDownloadDoesNotPublishPackage() async throws {
        try await ExtensionInstallFixtures.withTempDirectory { directory in
            let source = ExtensionInstallFixtures.makeSource()
            let archive = directory.appending(path: "demo.zip")
            try ExtensionInstallFixtures.makeArchive([
                .file("demo/extension.json", try ExtensionInstallFixtures.manifestJSON())
            ], at: archive)
            let provider = LocalPackageProvider(archiveURL: archive, delay: .seconds(5))
            let store = LanguageExtensionStore(extensionsDirectory: directory.appending(path: "Extensions"))
            let installer = try makeInstaller(store: store, providers: [provider])
            let candidate = ExtensionInstallFixtures.makeCandidate(source: source)

            let task = Task {
                try await installer.install(candidate: candidate, from: source, progress: { _ in })
            }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()

            var didCancel = false
            do {
                _ = try await task.value
            } catch is CancellationError {
                didCancel = true
            } catch ExtensionSourceProviderError.cancelled {
                didCancel = true
            }
            #expect(didCancel)
            #expect(store.globalExtensions().isEmpty)
        }
    }

    private func makeInstaller(
        store: LanguageExtensionStore,
        providers: [any ExtensionSourceProvider]
    ) throws -> ExtensionPackageInstaller {
        ExtensionPackageInstaller(
            store: store,
            providers: try ExtensionSourceProviderRegistry(providers: providers)
        )
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ExtensionInstallPhase] = []

    var phases: [ExtensionInstallPhase] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func append(_ progress: ExtensionInstallProgress) {
        lock.lock()
        recorded.append(progress.phase)
        lock.unlock()
    }
}
