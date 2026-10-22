import Foundation

enum ExtensionInstallationState: Equatable {
    case idle
    case preparing
    case downloading(completedBytes: Int64, totalBytes: Int64?, fraction: Double?)
    case extracting(fraction: Double)
    case validating
    case installing
    case cancelling
    case succeeded(version: String)
    case cancelled
    case failed(message: String)

    var isInProgress: Bool {
        switch self {
        case .preparing, .downloading, .extracting, .validating, .installing, .cancelling:
            true
        case .idle, .succeeded, .cancelled, .failed:
            false
        }
    }
}

@MainActor
final class ExtensionInstallationViewModel: ObservableObject {
    @Published private(set) var states: [ExtensionCatalogCandidateID: ExtensionInstallationState] = [:]

    private let installer: ExtensionPackageInstaller
    private let languageManager: LanguageExtensionManager
    private var tasks: [ExtensionCatalogCandidateID: Task<Void, Never>] = [:]

    init(
        installer: ExtensionPackageInstaller? = nil,
        languageManager: LanguageExtensionManager? = nil
    ) {
        self.installer = installer ?? ExtensionPackageInstaller(
            store: AppServices.languageExtensionStore,
            providers: AppServices.extensionSourceProviders
        )
        self.languageManager = languageManager ?? AppServices.languageExtensionManager
    }

    func state(for candidateID: ExtensionCatalogCandidateID) -> ExtensionInstallationState {
        states[candidateID] ?? .idle
    }

    func install(_ candidate: ExtensionCatalogCandidate, from source: ExtensionSource) {
        guard tasks[candidate.id] == nil else { return }
        let consentBefore = languageManager.nativeGrammarConsentSnapshot
        states[candidate.id] = .preparing

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let installed = try await installer.install(
                    candidate: candidate,
                    from: source,
                    progress: { [weak self] update in
                        Task { @MainActor in
                            self?.apply(update, for: candidate.id)
                        }
                    }
                )
                languageManager.completeMarketplaceInstall(installed, consentBefore: consentBefore)
                states[candidate.id] = .succeeded(version: installed.version ?? candidate.version)
            } catch is CancellationError {
                states[candidate.id] = .cancelled
            } catch ExtensionInstallationError.cancelled {
                states[candidate.id] = .cancelled
            } catch {
                states[candidate.id] = .failed(message: error.localizedDescription)
            }
            tasks[candidate.id] = nil
        }
        tasks[candidate.id] = task
    }

    func cancel(_ candidateID: ExtensionCatalogCandidateID) {
        guard let task = tasks[candidateID] else { return }
        states[candidateID] = .cancelling
        task.cancel()
    }

    func clear(_ candidateID: ExtensionCatalogCandidateID) {
        guard tasks[candidateID] == nil else { return }
        states[candidateID] = .idle
    }

    private func apply(_ update: ExtensionInstallProgress, for candidateID: ExtensionCatalogCandidateID) {
        if case .cancelling = state(for: candidateID) { return }
        switch update.phase {
        case .preparing:
            states[candidateID] = .preparing
        case .downloading:
            states[candidateID] = .downloading(
                completedBytes: update.completedBytes,
                totalBytes: update.totalBytes,
                fraction: update.fraction
            )
        case .extracting:
            states[candidateID] = .extracting(fraction: update.fraction ?? 0)
        case .validating:
            states[candidateID] = .validating
        case .installing:
            states[candidateID] = .installing
        case .finished:
            break
        }
    }
}
