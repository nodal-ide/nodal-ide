import Foundation

enum ExtensionInstallPhase: Equatable, Sendable {
    case preparing
    case downloading
    case extracting
    case validating
    case installing
    case finished
}

struct ExtensionInstallProgress: Equatable, Sendable {
    let phase: ExtensionInstallPhase
    let completedBytes: Int64
    let totalBytes: Int64?
    let fraction: Double?
}

enum ExtensionInstallationError: LocalizedError, Equatable {
    case sourceMismatch
    case sourceDisabled
    case sourceUntrusted
    case providerUnavailable
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMismatch:
            return "The selected extension does not belong to this source."
        case .sourceDisabled:
            return "Enable the source before installing this extension."
        case .sourceUntrusted:
            return "Trust the source before installing this extension."
        case .providerUnavailable:
            return "No provider is available for this source."
        case .cancelled:
            return "The installation was cancelled."
        case .failed(let message):
            return message
        }
    }
}

/// Downloads, verifies, extracts, and transactionally installs a catalog package.
actor ExtensionPackageInstaller {
    private let store: LanguageExtensionStore
    private let providers: ExtensionSourceProviderRegistry?
    private let extractor: ExtensionArchiveExtractor

    init(
        store: LanguageExtensionStore,
        providers: ExtensionSourceProviderRegistry?,
        extractor: ExtensionArchiveExtractor = ExtensionArchiveExtractor()
    ) {
        self.store = store
        self.providers = providers
        self.extractor = extractor
    }

    func install(
        candidate: ExtensionCatalogCandidate,
        from source: ExtensionSource,
        progress: @escaping @Sendable (ExtensionInstallProgress) -> Void
    ) async throws -> InstalledLanguageExtension {
        guard source.id == candidate.sourceID else { throw ExtensionInstallationError.sourceMismatch }
        guard source.isEnabled else { throw ExtensionInstallationError.sourceDisabled }
        guard source.isTrusted else { throw ExtensionInstallationError.sourceUntrusted }
        guard let providers else { throw ExtensionInstallationError.providerUnavailable }
        let provider = try providers.provider(for: source)

        let reporter = ExtensionInstallProgressReporter(progress: progress)
        reporter.report(phase: .preparing)

        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory
            .appending(path: "NodalExtensionInstalls", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let packageURL = stagingRoot.appending(path: "package.zip", directoryHint: .notDirectory)
        let extractedRoot = stagingRoot.appending(path: "extracted", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let downloaded = try await provider.download(
            candidate.package,
            from: source,
            to: packageURL,
            progress: { completed, total in
                reporter.reportDownload(completed: completed, total: total)
            }
        )
        try Task.checkCancellation()

        reporter.report(phase: .extracting)
        let packRoot = try extractor.extract(
            archiveAt: downloaded.fileURL,
            to: extractedRoot,
            progress: { reporter.reportExtraction(fraction: $0) }
        )
        try Task.checkCancellation()

        reporter.report(phase: .validating)
        let provenance = ExtensionProvenance(
            source: source,
            extensionID: candidate.extensionID,
            version: candidate.version,
            integrity: candidate.package.integrity
        )
        reporter.report(phase: .installing)
        let installed = try store.install(
            packageAt: packRoot,
            provenance: provenance,
            expectedIdentity: ExtensionPackageIdentity(
                extensionID: candidate.extensionID,
                version: candidate.version
            )
        )

        reporter.report(phase: .finished)
        return installed
    }
}

/// Throttles byte-level download callbacks so UI work is bounded by percentage, not chunk count.
private final class ExtensionInstallProgressReporter: @unchecked Sendable {
    private let progress: @Sendable (ExtensionInstallProgress) -> Void
    private let lock = NSLock()
    private var lastPercent = -1
    private var extractionPercent = -1

    init(progress: @escaping @Sendable (ExtensionInstallProgress) -> Void) {
        self.progress = progress
    }

    func reportDownload(completed: Int64, total: Int64?) {
        let percent: Int
        if let total, total > 0 {
            percent = Int((Double(completed) / Double(total)) * 100)
        } else {
            percent = Int(completed / (1_024 * 1_024))
        }
        lock.lock()
        guard percent != lastPercent else {
            lock.unlock()
            return
        }
        lastPercent = percent
        lock.unlock()
        report(
            ExtensionInstallProgress(
                phase: .downloading,
                completedBytes: completed,
                totalBytes: total,
                fraction: total.flatMap { $0 > 0 ? Double(completed) / Double($0) : nil }
            )
        )
    }

    func reportExtraction(fraction: Double) {
        let percent = Int((fraction * 100).rounded())
        lock.lock()
        guard percent != extractionPercent else {
            lock.unlock()
            return
        }
        extractionPercent = percent
        lock.unlock()
        report(
            ExtensionInstallProgress(
                phase: .extracting,
                completedBytes: 0,
                totalBytes: nil,
                fraction: fraction
            )
        )
    }

    func report(phase: ExtensionInstallPhase) {
        report(ExtensionInstallProgress(phase: phase, completedBytes: 0, totalBytes: nil, fraction: nil))
    }

    private func report(_ value: ExtensionInstallProgress) {
        DispatchQueue.main.async { [progress] in
            progress(value)
        }
    }
}
