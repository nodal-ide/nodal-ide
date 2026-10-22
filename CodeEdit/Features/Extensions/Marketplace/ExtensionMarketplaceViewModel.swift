import Combine
import Foundation

@MainActor
final class ExtensionMarketplaceViewModel: ObservableObject {
    @Published private(set) var catalogs: [ExtensionSourceID: ExtensionCatalog] = [:]
    @Published private(set) var sourceStates: [ExtensionSourceID: ExtensionSourceCatalogState] = [:]
    @Published private(set) var sourceNames: [ExtensionSourceID: String] = [:]
    @Published private(set) var candidates: [ExtensionCatalogCandidate] = []
    @Published private(set) var isRefreshing = false
    @Published var selectedSourceID: ExtensionSourceID? {
        didSet { rebuildCandidates() }
    }
    @Published var searchText = "" {
        didSet { rebuildCandidates() }
    }

    private let sourceStore: ExtensionSourceStore
    private let catalogService: ExtensionCatalogService
    private let providers: ExtensionSourceProviderRegistry?

    init(
        sourceStore: ExtensionSourceStore? = nil,
        catalogService: ExtensionCatalogService = ExtensionCatalogService()
    ) {
        let resolvedSourceStore = sourceStore ?? AppServices.extensionSourceStore
        self.sourceStore = resolvedSourceStore
        self.catalogService = catalogService
        self.providers = try? ExtensionSourceProviderRegistry(providers: [HTTPSStaticIndexProvider()])
        sourceNames = resolvedSourceStore.sources.reduce(into: [:]) { names, source in
            names[source.id] = source.name
        }
        rebuildCandidates()
        Task { await loadCachedCatalogs() }
    }

    var sources: [ExtensionSource] { sourceStore.sources }

    private func rebuildCandidates() {
        let sourceByID = sources.reduce(into: [ExtensionSourceID: ExtensionSource]()) { indexed, source in
            indexed[source.id] = source
        }
        var rebuiltCandidates: [ExtensionCatalogCandidate] = []

        for (sourceID, catalog) in catalogs {
            guard let source = sourceByID[sourceID],
                  source.isEnabled,
                  source.isTrusted,
                  selectedSourceID == nil || selectedSourceID == sourceID
            else {
                continue
            }

            for (extensionID, entry) in catalog.extensions {
                guard let package = entry.versions[entry.latest] else {
                    continue
                }

                let candidate = ExtensionCatalogCandidate(
                    sourceID: sourceID,
                    extensionID: extensionID,
                    version: entry.latest,
                    entry: entry,
                    package: package
                )

                guard matchesSearch(candidate) else {
                    continue
                }

                rebuiltCandidates.append(candidate)
            }
        }

        candidates = rebuiltCandidates.sorted {
            let nameOrder = $0.entry.name.localizedStandardCompare($1.entry.name)

            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            if $0.entry.publisher != $1.entry.publisher {
                return $0.entry.publisher.localizedStandardCompare(
                    $1.entry.publisher
                ) == .orderedAscending
            }

            if $0.sourceID != $1.sourceID {
                return $0.sourceID.rawValue.uuidString
                    < $1.sourceID.rawValue.uuidString
            }

            return $0.extensionID < $1.extensionID
        }
    }

    func state(for sourceID: ExtensionSourceID) -> ExtensionSourceCatalogState {
        sourceStates[sourceID] ?? .idle
    }

    func cachedCatalog(for sourceID: ExtensionSourceID) -> ExtensionCatalog? {
        catalogs[sourceID]
    }

    func loadCachedCatalogs() async {
        for source in sources {
            do {
                if let cached = try await catalogService.cachedCatalog(for: source.id) {
                    catalogs[source.id] = cached.catalog
                    let timeToLive = source.refreshInterval ?? ExtensionCatalogService.defaultTimeToLive
                    let cacheAge = Date.now.timeIntervalSince(cached.fetchedAt)
                    if !source.isEnabled {
                        sourceStates[source.id] = .disabled
                    } else if !source.isTrusted {
                        sourceStates[source.id] = .untrusted
                    } else if cacheAge >= 0, cacheAge < timeToLive {
                        sourceStates[source.id] = .fresh(
                            fetchedAt: cached.fetchedAt,
                            extensionCount: cached.catalog.extensions.count
                        )
                    } else {
                        sourceStates[source.id] = .stale(
                            fetchedAt: cached.fetchedAt,
                            failure: .unavailable
                        )
                    }
                }
                if sourceStates[source.id] == nil {
                    sourceStates[source.id] = await catalogService.state(for: source.id)
                }
            } catch {
                sourceStates[source.id] = .invalid(.cacheUnavailable)
            }
        }
        rebuildCandidates()
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
        rebuildCandidates()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for source in sources where source.isEnabled && source.isTrusted {
            await refresh(source)
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
        rebuildCandidates()
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
        rebuildCandidates()
    }

    func setEnabled(_ enabled: Bool, for source: ExtensionSource) throws {
        try sourceStore.setEnabled(enabled, for: source.id)
        sourceStates[source.id] = enabled ? .idle : .disabled
        rebuildCandidates()
    }

    func setTrusted(_ trusted: Bool, for source: ExtensionSource) throws {
        try sourceStore.setTrusted(trusted, for: source.id)
        sourceStates[source.id] = trusted ? .idle : .untrusted
        rebuildCandidates()
    }

    func remove(_ source: ExtensionSource) async throws {
        try await catalogService.removeSource(source.id)
        try await sourceStore.remove(source.id)
        sourceNames.removeValue(forKey: source.id)
        catalogs.removeValue(forKey: source.id)
        sourceStates.removeValue(forKey: source.id)
        if selectedSourceID == source.id { selectedSourceID = nil }
        rebuildCandidates()
    }

    func sourceName(for sourceID: ExtensionSourceID) -> String {
        sourceNames[sourceID] ?? "Unknown Source"
    }

    private func matchesSearch(_ candidate: ExtensionCatalogCandidate) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return candidate.entry.name.localizedCaseInsensitiveContains(query)
            || candidate.entry.description.localizedCaseInsensitiveContains(query)
            || candidate.entry.publisher.localizedCaseInsensitiveContains(query)
            || candidate.extensionID.localizedCaseInsensitiveContains(query)
    }
}
