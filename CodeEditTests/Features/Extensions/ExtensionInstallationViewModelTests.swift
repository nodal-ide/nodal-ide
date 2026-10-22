import Foundation
import Testing
import CodeEditLang
@testable import CodeEdit

@Suite
struct ExtensionInstallationViewModelTests {
    @Test
    @MainActor
    func lateProgressCannotOverwriteSuccessfulInstallation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = ExtensionInstallFixtures.makeSource()
        let extensionID = "com.example.late-progress"
        let candidate = ExtensionInstallFixtures.makeCandidate(
            source: source,
            extensionID: extensionID,
            version: "1.0.0"
        )
        let installed = makeInstalled(id: extensionID, version: "1.0.0", root: directory)
        let completer = StubCompleter()
        let installer = StubInstaller(installed: installed, sendsLateInstallingProgress: true)
        let viewModel = ExtensionInstallationViewModel(
            installer: installer,
            languageManager: completer
        )

        viewModel.install(candidate, from: source)

        #expect(
            await waitForState(viewModel, candidateID: candidate.id) {
                $0 == .succeeded(version: "1.0.0")
            } == .succeeded(version: "1.0.0")
        )

        try await Task.sleep(for: .milliseconds(150))

        #expect(viewModel.state(for: candidate.id) == .succeeded(version: "1.0.0"))
        #expect(completer.completed.count == 1)
    }

    @Test
    @MainActor
    func removingExtensionResetsMarketplaceInstallState() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = ExtensionInstallFixtures.makeSource()
        let extensionID = "com.example.removal"
        let candidate = ExtensionInstallFixtures.makeCandidate(
            source: source,
            extensionID: extensionID,
            version: "1.0.0"
        )
        let installed = makeInstalled(id: extensionID, version: "1.0.0", root: directory)
        let completer = StubCompleter()
        let viewModel = ExtensionInstallationViewModel(
            installer: StubInstaller(installed: installed),
            languageManager: completer
        )

        viewModel.install(candidate, from: source)
        #expect(
            await waitForState(viewModel, candidateID: candidate.id) {
                $0 == .succeeded(version: "1.0.0")
            } == .succeeded(version: "1.0.0")
        )

        NotificationCenter.default.post(
            name: LanguageExtensionManager.didRemoveExtensionNotification,
            object: nil,
            userInfo: [LanguageExtensionManager.removedExtensionIDKey: candidate.extensionID]
        )

        #expect(
            await waitForState(viewModel, candidateID: candidate.id) { $0 == .idle } == .idle
        )
    }

    @MainActor
    private func waitForState(
        _ viewModel: ExtensionInstallationViewModel,
        candidateID: ExtensionCatalogCandidateID,
        matching predicate: (ExtensionInstallationState) -> Bool,
        attempts: Int = 100
    ) async -> ExtensionInstallationState {
        for _ in 0..<attempts {
            let state = viewModel.state(for: candidateID)
            if predicate(state) { return state }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return viewModel.state(for: candidateID)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ExtensionInstallationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeInstalled(id: String, version: String, root: URL) -> InstalledLanguageExtension {
        let manifest = LanguageExtensionManifest(
            schemaVersion: 2,
            id: id,
            name: "Demo",
            version: version,
            type: "languagePack"
        )
        return InstalledLanguageExtension(
            id: manifest.id,
            name: manifest.name,
            version: version,
            root: root,
            manifest: manifest,
            scope: .global
        )
    }
}

private final class StubCompleter: ExtensionInstallationCompleting {
    var nativeGrammarConsentSnapshot: [String: String] = [:]
    private(set) var completed: [InstalledLanguageExtension] = []

    func completeMarketplaceInstall(
        _ ext: InstalledLanguageExtension,
        consentBefore: [String: String]
    ) {
        completed.append(ext)
    }
}

private final class StubInstaller: ExtensionInstalling, @unchecked Sendable {
    private let installed: InstalledLanguageExtension
    private let sendsLateInstallingProgress: Bool

    init(installed: InstalledLanguageExtension, sendsLateInstallingProgress: Bool = false) {
        self.installed = installed
        self.sendsLateInstallingProgress = sendsLateInstallingProgress
    }

    func install(
        candidate: ExtensionCatalogCandidate,
        from source: ExtensionSource,
        progress: @escaping @Sendable (ExtensionInstallProgress) -> Void
    ) async throws -> InstalledLanguageExtension {
        progress(ExtensionInstallProgress(
            phase: .installing,
            completedBytes: 0,
            totalBytes: nil,
            fraction: nil
        ))

        if sendsLateInstallingProgress {
            Task.detached {
                try? await Task.sleep(for: .milliseconds(50))
                progress(ExtensionInstallProgress(
                    phase: .installing,
                    completedBytes: 0,
                    totalBytes: nil,
                    fraction: nil
                ))
            }
        }

        return installed
    }
}
