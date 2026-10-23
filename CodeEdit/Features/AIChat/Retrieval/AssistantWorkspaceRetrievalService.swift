import Foundation

@MainActor
final class AssistantWorkspaceRetrievalService: AssistantRetrievalProviding {
    private let index: AssistantRetrievalIndex
    private var statusHandler: ((AssistantRetrievalStatus) -> Void)?
    private var buildTask: Task<Void, Never>?
    private var lastBuildAt: Date?
    private let refreshInterval: TimeInterval = 20

    private(set) var status = AssistantRetrievalStatus.idle {
        didSet {
            statusHandler?(status)
        }
    }

    init(rootURL: URL, storageRoot: URL? = nil) {
        index = AssistantRetrievalIndex(rootURL: rootURL, storageRoot: storageRoot)
    }

    func setStatusHandler(_ handler: ((AssistantRetrievalStatus) -> Void)?) {
        statusHandler = handler
        handler?(status)
    }

    func start() {
        guard buildTask == nil, !status.isIndexing, !status.isReady else { return }
        status = .indexing(completed: 0, total: 0)
        buildTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.index.prepare { [weak self] completed, total in
                await self?.updateProgress(completed: completed, total: total)
            }
            guard !Task.isCancelled else { return }
            self.finishBuild(result)
        }
    }

    func stop() {
        buildTask?.cancel()
        buildTask = nil
        if status.isIndexing {
            status = .idle
        }
    }

    func rebuild() {
        buildTask?.cancel()
        status = .indexing(completed: 0, total: 0)
        buildTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.index.rebuild { [weak self] completed, total in
                await self?.updateProgress(completed: completed, total: total)
            }
            guard !Task.isCancelled else { return }
            self.finishBuild(result)
        }
    }

    func clear() {
        buildTask?.cancel()
        buildTask = nil
        status = .idle
        Task { [index] in
            await index.clear()
        }
    }

    func retrieve(_ query: AssistantRetrievalQuery) async -> AssistantRetrievalResult {
        guard !query.isEmpty else { return .empty }
        async let code = index.search(query)
        let knowledge = AssistantKnowledgeRetriever.retrieve(query: query.text)
        let result = await AssistantRetrievalResult(code: code, knowledge: knowledge)
        refreshInBackgroundIfNeeded()
        return result
    }

    private func updateProgress(completed: Int, total: Int) {
        guard status.isIndexing else { return }
        status = .indexing(completed: completed, total: total)
    }

    private func finishBuild(_ result: AssistantRetrievalStatus) {
        buildTask = nil
        lastBuildAt = Date()
        status = result
    }

    private func refreshInBackgroundIfNeeded() {
        guard buildTask == nil,
              status.isReady,
              Date().timeIntervalSince(lastBuildAt ?? .distantPast) >= refreshInterval
        else { return }

        buildTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.index.prepare { _, _ in }
            guard !Task.isCancelled else { return }
            self.finishBuild(result)
        }
    }
}
