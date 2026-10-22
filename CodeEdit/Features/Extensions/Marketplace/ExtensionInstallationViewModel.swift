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

protocol ExtensionInstalling {
    func install(
        candidate: ExtensionCatalogCandidate,
        from source: ExtensionSource,
        progress: @escaping @Sendable (ExtensionInstallProgress) -> Void
    ) async throws -> InstalledLanguageExtension
}

extension ExtensionPackageInstaller: ExtensionInstalling {}

@MainActor
protocol ExtensionInstallationCompleting: AnyObject {
    var nativeGrammarConsentSnapshot: [String: String] { get }
    func completeMarketplaceInstall(
        _ ext: InstalledLanguageExtension,
        consentBefore: [String: String]
    )
}

extension LanguageExtensionManager: ExtensionInstallationCompleting {}

@MainActor
final class ExtensionInstallationViewModel: ObservableObject {
    @Published private(set) var states: [ExtensionCatalogCandidateID: ExtensionInstallationState] = [:]

    private let installer: any ExtensionInstalling
    private let languageManager: any ExtensionInstallationCompleting
    private var tasks: [ExtensionCatalogCandidateID: Task<Void, Never>] = [:]
    private var removedExtensionIDs: Set<String> = []
    private var removalObserver: NSObjectProtocol?

    init(
        installer: (any ExtensionInstalling)? = nil,
        languageManager: (any ExtensionInstallationCompleting)? = nil
    ) {
        self.installer = installer ?? ExtensionPackageInstaller(
            store: AppServices.languageExtensionStore,
            providers: AppServices.extensionSourceProviders
        )
        self.languageManager = languageManager ?? AppServices.languageExtensionManager
        removalObserver = NotificationCenter.default.addObserver(
            forName: LanguageExtensionManager.didRemoveExtensionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let extensionID = notification.userInfo?[
                LanguageExtensionManager.removedExtensionIDKey
            ] as? String else { return }
            Task { @MainActor in
                self?.extensionWasRemoved(extensionID)
            }
        }
    }

    deinit {
        if let removalObserver {
            NotificationCenter.default.removeObserver(removalObserver)
        }
    }

    func state(for candidateID: ExtensionCatalogCandidateID) -> ExtensionInstallationState {
        states[candidateID] ?? .idle
    }

    func install(_ candidate: ExtensionCatalogCandidate, from source: ExtensionSource) {
        guard tasks[candidate.id] == nil else { return }
        let consentBefore = languageManager.nativeGrammarConsentSnapshot
        removedExtensionIDs.remove(candidate.extensionID)
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
                finishSuccessfully(installed, candidate: candidate, consentBefore: consentBefore)
            } catch is CancellationError {
                finish(with: .cancelled, candidate: candidate)
            } catch ExtensionInstallationError.cancelled {
                finish(with: .cancelled, candidate: candidate)
            } catch {
                finish(with: .failed(message: error.localizedDescription), candidate: candidate)
            }
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

    private func finishSuccessfully(
        _ installed: InstalledLanguageExtension,
        candidate: ExtensionCatalogCandidate,
        consentBefore: [String: String]
    ) {
        guard !removedExtensionIDs.contains(candidate.extensionID) else {
            finish(with: .idle, candidate: candidate)
            return
        }

        states[candidate.id] = .succeeded(version: installed.version ?? candidate.version)
        tasks[candidate.id] = nil

        let languageManager = languageManager
        Task { @MainActor in
            await Task.yield()
            languageManager.completeMarketplaceInstall(installed, consentBefore: consentBefore)
        }
    }

    private func finish(
        with state: ExtensionInstallationState,
        candidate: ExtensionCatalogCandidate
    ) {
        states[candidate.id] = removedExtensionIDs.contains(candidate.extensionID) ? .idle : state
        tasks[candidate.id] = nil
    }

    private func extensionWasRemoved(_ extensionID: String) {
        removedExtensionIDs.insert(extensionID)
        let candidateIDs = Set(states.keys).union(tasks.keys)
        for candidateID in candidateIDs where candidateID.extensionID == extensionID {
            tasks[candidateID]?.cancel()
            tasks[candidateID] = nil
            states[candidateID] = .idle
        }
    }

    private func apply(_ update: ExtensionInstallProgress, for candidateID: ExtensionCatalogCandidateID) {
        guard state(for: candidateID).isInProgress else { return }
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
