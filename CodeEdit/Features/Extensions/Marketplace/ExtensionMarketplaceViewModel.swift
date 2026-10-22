import Combine
import Foundation

/// Aggregate health of the configured sources, used to explain cached/offline browsing states.
struct ExtensionSourceHealth: Equatable, Sendable {
    var isLoadingCatalogs = false
    var isRefreshing = false
    var staleCount = 0
    var offlineCount = 0
    var invalidCount = 0

    var hasIssues: Bool {
        staleCount + offlineCount + invalidCount > 0
    }

    var notice: ExtensionSourceHealthNotice? {
        guard hasIssues else { return nil }

        var counts: [String] = []
        if staleCount > 0 { counts.append("\(staleCount) stale") }
        if offlineCount > 0 { counts.append("\(offlineCount) offline") }
        if invalidCount > 0 { counts.append("\(invalidCount) invalid") }

        let title: String
        if invalidCount > 0 {
            title = "Some sources could not be refreshed"
        } else if offlineCount > 0 {
            title = "Some sources are offline"
        } else {
            title = "Showing cached catalog data"
        }
        return ExtensionSourceHealthNotice(
            title: title,
            detail: "\(counts.joined(separator: " · ")). Results may be out of date until a refresh succeeds."
        )
    }
}

struct ExtensionSourceHealthNotice: Equatable {
    let title: String
    let detail: String
}

@MainActor
final class ExtensionMarketplaceViewModel: ObservableObject {
    @Published private(set) var catalogs: [ExtensionSourceID: ExtensionCatalog] = [:]
    @Published private(set) var sourceStates: [ExtensionSourceID: ExtensionSourceCatalogState] = [:]
    @Published private(set) var sourceNames: [ExtensionSourceID: String] = [:]
    @Published private(set) var candidates: [ExtensionCatalogCandidate] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingCachedCatalogs = false
    @Published var selectedSourceID: ExtensionSourceID? {
        didSet { rebuildIndex() }
    }
    @Published var searchText = "" {
        didSet { applySearchFilter() }
    }

    private static let maximumConcurrentRefreshes = 4

    private let sourceStore: ExtensionSourceStore
    private let catalogService: ExtensionCatalogService
    private let providers: ExtensionSourceProviderRegistry?

    private var catalogIndex = ExtensionCatalogIndex(
        catalogs: [:],
        sources: [],
        selectedSourceID: nil
    )
    private var didLoadCachedCatalogs = false

    init(
        sourceStore: ExtensionSourceStore? = nil,
        catalogService: ExtensionCatalogService? = nil,
        providers: ExtensionSourceProviderRegistry? = nil
    ) {
        let resolvedSourceStore = sourceStore ?? AppServices.extensionSourceStore
        self.sourceStore = resolvedSourceStore
        self.catalogService = catalogService ?? AppServices.extensionCatalogService
        self.providers = providers ?? AppServices.extensionSourceProviders
        sourceNames = resolvedSourceStore.sources.reduce(into: [:]) { names, source in
            names[source.id] = source.name
        }
        rebuildIndex()
    }

    var sources: [ExtensionSource] { sourceStore.sources }

    var hasRefreshableSources: Bool {
        sources.contains { $0.isEnabled && $0.isTrusted }
    }

    var hasEnabledUntrustedSources: Bool {
        sources.contains { $0.isEnabled && !$0.isTrusted }
    }

    var hasSearchOrSourceFilter: Bool {
        selectedSourceID != nil
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var indexedCandidateCount: Int { catalogIndex.count }

    var sourceHealth: ExtensionSourceHealth {
        var health = ExtensionSourceHealth(
            isLoadingCatalogs: isLoadingCachedCatalogs,
            isRefreshing: isRefreshing
        )
        for source in sources {
            switch state(for: source.id) {
            case .stale:
                health.staleCount += 1
            case .offline:
                health.offlineCount += 1
            case .invalid:
                health.invalidCount += 1
            case .idle, .loading, .fresh, .untrusted, .disabled:
                break
            }
        }
        return health
    }

    func state(for sourceID: ExtensionSourceID) -> ExtensionSourceCatalogState {
        sourceStates[sourceID] ?? .idle
    }

    func isShowingCachedData(for sourceID: ExtensionSourceID) -> Bool {
        switch state(for: sourceID) {
        case .stale, .offline:
            return true
        case .idle, .loading, .fresh, .invalid, .untrusted, .disabled:
            return false
        }
    }

    func cachedCatalog(for sourceID: ExtensionSourceID) -> ExtensionCatalog? {
        catalogs[sourceID]
    }

    func candidate(for id: ExtensionCatalogCandidateID) -> ExtensionCatalogCandidate? {
        catalogIndex.candidate(for: id)
    }

    func loadCachedCatalogs() async {
        guard !didLoadCachedCatalogs, !isLoadingCachedCatalogs else { return }
        isLoadingCachedCatalogs = true
        defer {
            isLoadingCachedCatalogs = false
            didLoadCachedCatalogs = true
        }

        var loadedCatalogs = catalogs
        var loadedStates = sourceStates
        for source in sources {
            do {
                if let cached = try await catalogService.cachedCatalog(for: source.id) {
                    loadedCatalogs[source.id] = cached.catalog
                    let timeToLive = source.refreshInterval ?? ExtensionCatalogService.defaultTimeToLive
                    let cacheAge = Date.now.timeIntervalSince(cached.fetchedAt)
                    if !source.isEnabled {
                        loadedStates[source.id] = .disabled
                    } else if !source.isTrusted {
                        loadedStates[source.id] = .untrusted
                    } else if cacheAge >= 0, cacheAge < timeToLive {
                        loadedStates[source.id] = .fresh(
                            fetchedAt: cached.fetchedAt,
                            extensionCount: cached.catalog.extensions.count
                        )
                    } else {
                        loadedStates[source.id] = .stale(
                            fetchedAt: cached.fetchedAt,
                            failure: .unavailable
                        )
                    }
                }
                if loadedStates[source.id] == nil {
                    loadedStates[source.id] = await catalogService.state(for: source.id)
                }
            } catch {
                loadedStates[source.id] = .invalid(.cacheUnavailable)
            }
        }
        catalogs = loadedCatalogs
        sourceStates = loadedStates
        rebuildIndex()
    }

    func refresh(_ source: ExtensionSource, force: Bool = true) async {
        guard source.isEnabled else {
            sourceStates[source.id] = .disabled
            return
        }
        guard source.isTrusted else {
            sourceStates[source.id] = .untrusted
            return
        }
        guard let providers else {
            sourceStates[source.id] = .invalid(.providerUnavailable)
            return
        }
        sourceStates[source.id] = .loading(cachedAt: nil)
        let result = await catalogService.refresh(source: source, providers: providers, force: force)
        sourceStates[source.id] = result
        do {
            if let cached = try await catalogService.cachedCatalog(for: source.id) {
                catalogs[source.id] = cached.catalog
            }
        } catch {
            sourceStates[source.id] = .invalid(.cacheUnavailable)
        }
        rebuildIndex()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for source in sources where !source.isEnabled {
            sourceStates[source.id] = .disabled
        }
        for source in sources where source.isEnabled && !source.isTrusted {
            sourceStates[source.id] = .untrusted
        }

        let refreshableSources = sources.filter { $0.isEnabled && $0.isTrusted }
        await withTaskGroup(of: Void.self) { group in
            var iterator = refreshableSources.makeIterator()
            var running = 0
            while running < Self.maximumConcurrentRefreshes, let source = iterator.next() {
                group.addTask { await self.refresh(source) }
                running += 1
            }
            while await group.next() != nil {
                if let source = iterator.next() {
                    group.addTask { await self.refresh(source) }
                }
            }
        }
    }

    func addSource(name: String, location: URL, trustImmediately: Bool) throws {
        var source = ExtensionSource(
            name: name,
            providerID: .httpsStaticIndex,
            location: location,
            isTrusted: false
        )
        if trustImmediately {
            source.isTrusted = true
            source.trustChangedAt = .now
        }
        try sourceStore.add(source)
        sourceNames[source.id] = source.name
        sourceStates[source.id] = source.isTrusted ? .idle : .untrusted
        selectedSourceID = source.id
        rebuildIndex()
    }

    func updateSource(_ source: ExtensionSource, name: String, location: URL) async throws {
        var updated = source
        updated.name = name
        updated.location = location
        if source.location != location {
            try await catalogService.removeSource(source.id)
            catalogs.removeValue(forKey: source.id)
        }
        try sourceStore.update(updated)
        sourceNames[source.id] = name
        if source.location != location {
            sourceStates[source.id] = source.isTrusted ? .idle : .untrusted
        }
        rebuildIndex()
    }

    func setEnabled(_ enabled: Bool, for source: ExtensionSource) throws {
        try sourceStore.setEnabled(enabled, for: source.id)
        sourceStates[source.id] = enabled ? .idle : .disabled
        rebuildIndex()
    }

    func setTrusted(_ trusted: Bool, for source: ExtensionSource) throws {
        try sourceStore.setTrusted(trusted, for: source.id)
        sourceStates[source.id] = trusted ? .idle : .untrusted
        rebuildIndex()
    }

    func remove(_ source: ExtensionSource) async throws {
        try await catalogService.removeSource(source.id)
        try await sourceStore.remove(source.id)
        sourceNames.removeValue(forKey: source.id)
        catalogs.removeValue(forKey: source.id)
        sourceStates.removeValue(forKey: source.id)
        if selectedSourceID == source.id { selectedSourceID = nil }
        rebuildIndex()
    }

    func sourceName(for sourceID: ExtensionSourceID) -> String {
        sourceNames[sourceID] ?? "Unknown Source"
    }

    func source(for sourceID: ExtensionSourceID) -> ExtensionSource? {
        sources.first { $0.id == sourceID }
    }

    /// Rebuilds the ordered candidate index once per catalog/source/filter change. Search filtering
    /// only walks the precomputed index, so typing never reindexes or re-sorts the catalog.
    private func rebuildIndex() {
        catalogIndex = ExtensionCatalogIndex(
            catalogs: catalogs,
            sources: sources,
            selectedSourceID: selectedSourceID
        )
        applySearchFilter()
    }

    private func applySearchFilter() {
        candidates = catalogIndex.candidates(matching: searchText)
    }
}
