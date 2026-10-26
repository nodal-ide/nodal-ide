import Combine
import Foundation
import CodeEditLang
import CodeEditLangPHP
import CodeEditSourceEditor

@MainActor
final class ReferencesSession: ObservableObject {
    @Published private(set) var phase: ReferencesPhase = .idle
    @Published private(set) var target: ReferenceTarget?
    @Published private(set) var groups: [ReferenceFileGroup] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var isComplete = true

    static let timeout: TimeInterval = 10

    private weak var workspace: WorkspaceDocument?
    private let providerOverride: ((ReferenceQuery) -> (any ReferenceProviding)?)?
    private let timeout: TimeInterval
    private var queryTask: Task<ReferenceQueryOutcome, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?
    private var generation = 0
    private var resolvedToken = -1

    init(
        providerOverride: ((ReferenceQuery) -> (any ReferenceProviding)?)? = nil,
        timeout: TimeInterval = ReferencesSession.timeout
    ) {
        self.providerOverride = providerOverride
        self.timeout = timeout
    }

    func configure(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    func findReferences() {
        guard let workspace else { return }
        switch ReferencesTargetCapture.capture(in: workspace) {
        case .unavailable(let reason):
            cancel()
            target = nil
            groups = []
            totalCount = 0
            isComplete = true
            phase = .unsupported(reason)
        case .captured(let query):
            run(query, workspace: workspace)
        }
    }

    func refresh() {
        findReferences()
    }

    func cancel() {
        generation += 1
        resolvedToken = -1
        queryTask?.cancel()
        queryTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        waitTask?.cancel()
        waitTask = nil
        if phase.isSearching {
            phase = .idle
        }
    }

    func clear() {
        cancel()
        target = nil
        groups = []
        totalCount = 0
        isComplete = true
        phase = .idle
    }

    func references(for url: URL) -> [EditorReference] {
        let key = url.standardizedFileURL
        return groups.first { $0.fileURL.standardizedFileURL == key }?.references ?? []
    }

    func run(_ query: ReferenceQuery, workspace: WorkspaceDocument? = nil) {
        cancel()
        let token = generation

        target = query.target
        groups = []
        totalCount = 0
        isComplete = true
        phase = .searching

        let provider = providerOverride?(query)
            ?? workspace.flatMap { makeProvider(for: query, workspace: $0) }
        guard let provider else {
            phase = .unsupported("Find references isn't available for \(query.languageID).")
            return
        }

        let request = Task { await provider.references(for: query) }
        queryTask = request

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            request.cancel()
            self?.finish(.failed(.timedOut), token: token)
        }

        waitTask = Task { [weak self] in
            let outcome = await request.value
            guard !Task.isCancelled else { return }
            self?.finish(outcome, token: token)
        }
    }

    private func finish(_ outcome: ReferenceQueryOutcome, token: Int) {
        guard token == generation, token != resolvedToken else { return }
        resolvedToken = token
        timeoutTask?.cancel()
        timeoutTask = nil
        queryTask = nil
        waitTask = nil
        apply(outcome)
    }

    private func apply(_ outcome: ReferenceQueryOutcome) {
        switch outcome {
        case .results(let references, let isComplete):
            groups = ReferenceFileGroup.group(references, root: workspaceURL)
            totalCount = references.count
            self.isComplete = isComplete
            phase = .results
        case .unsupported(let reason):
            groups = []
            totalCount = 0
            self.isComplete = true
            phase = .unsupported(reason)
        case .failed(let error):
            groups = []
            totalCount = 0
            self.isComplete = false
            phase = .failed(error)
        }
    }

    private var workspaceURL: URL? {
        workspace?.workspaceFileManager?.folderUrl ?? workspace?.fileURL
    }

    private func makeProvider(
        for query: ReferenceQuery,
        workspace: WorkspaceDocument
    ) -> (any ReferenceProviding)? {
        guard let root = query.workspaceRoot ?? workspace.fileURL else { return nil }

        let openLink: (JumpToDefinitionLink) -> Void = { [weak workspace] link in
            guard let workspace, let url = link.url else { return }
            workspace.editorManager?.revealSourceLocation(
                url: url,
                line: link.targetRange.start.line,
                column: link.targetRange.start.column
            )
        }

        let providers = AppServices.languageProviderRegistry.providers(
            for: query.target.fileURL,
            root: root,
            languageID: query.languageID,
            openLink: openLink
        )
        guard !providers.isEmpty else { return nil }

        let textProvider = AppSourceTextProvider.snapshot(in: workspace)
        for provider in providers {
            (provider as? LSPLanguageProvider)?.sourceTextProvider = textProvider
        }
        return LanguageProviderAggregator(providers: providers)
    }
}
