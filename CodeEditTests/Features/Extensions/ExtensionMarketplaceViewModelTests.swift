@testable import CodeEdit
import Combine
import Foundation
import Testing

@Suite
struct ExtensionMarketplaceViewModelTests {
    @Test
    @MainActor
    func indexesFixtureCatalogsAndFiltersWithoutLosingSourceProvenance() async throws {
        try await withTempDir { directory in
            let cache = ExtensionCatalogCache(directory: directory)
            let store = ExtensionSourceStore(
                settings: MemorySettingsStore(),
                catalogCache: cache,
                seedsDefaultSource: false
            )
            let first = makeSource(name: "First")
            let second = makeSource(name: "Second")
            try store.add(first)
            try store.add(second)
            try await cache.save(
                makeCachedCatalog(name: "Forge", publisher: "Nodal Samples"),
                for: first.id
            )
            try await cache.save(
                makeCachedCatalog(name: "Forge Clone", publisher: "Other"),
                for: second.id
            )

            let viewModel = ExtensionMarketplaceViewModel(
                sourceStore: store,
                catalogService: ExtensionCatalogService(cache: cache)
            )
            await viewModel.loadCachedCatalogs()

            #expect(viewModel.candidates.count == 2)
            #expect(viewModel.indexedCandidateCount == 2)
            #expect(!viewModel.hasSearchOrSourceFilter)
            #expect(Set(viewModel.candidates.map(\.sourceID)) == [first.id, second.id])
            #expect(viewModel.candidate(for: viewModel.candidates[0].id) == viewModel.candidates[0])

            viewModel.selectedSourceID = second.id
            #expect(viewModel.candidates.count == 1)
            #expect(viewModel.indexedCandidateCount == 1)
            #expect(viewModel.hasSearchOrSourceFilter)
            #expect(viewModel.candidates.first?.sourceID == second.id)

            viewModel.selectedSourceID = nil
            viewModel.searchText = "clone"
            #expect(viewModel.candidates.count == 1)
            #expect(viewModel.candidates.first?.sourceID == second.id)

            viewModel.searchText = "FORGE"
            #expect(viewModel.candidates.count == 2)
        }
    }

    @Test
    @MainActor
    func excludesUntrustedAndDisabledSourcesAndReactsToStateChanges() async throws {
        try await withTempDir { directory in
            let cache = ExtensionCatalogCache(directory: directory)
            let store = ExtensionSourceStore(
                settings: MemorySettingsStore(),
                catalogCache: cache,
                seedsDefaultSource: false
            )
            let trusted = makeSource(name: "Trusted", trusted: true)
            let untrusted = makeSource(name: "Untrusted", trusted: false)
            try store.add(trusted)
            try store.add(untrusted)
            try await cache.save(makeCachedCatalog(), for: trusted.id)
            try await cache.save(makeCachedCatalog(), for: untrusted.id)

            let viewModel = ExtensionMarketplaceViewModel(
                sourceStore: store,
                catalogService: ExtensionCatalogService(cache: cache)
            )
            await viewModel.loadCachedCatalogs()

            #expect(viewModel.candidates.map(\.sourceID) == [trusted.id])
            #expect(viewModel.state(for: untrusted.id) == .untrusted)
            #expect(viewModel.hasEnabledUntrustedSources)

            try viewModel.setTrusted(true, for: untrusted)
            #expect(viewModel.candidates.count == 2)
            #expect(!viewModel.hasEnabledUntrustedSources)

            try viewModel.setEnabled(false, for: untrusted)
            #expect(viewModel.candidates.map(\.sourceID) == [trusted.id])
            #expect(viewModel.state(for: untrusted.id) == .disabled)
        }
    }

    @Test
    @MainActor
    func refreshAllOnlyRefreshesTrustedEnabledSources() async throws {
        try await withTempDir { directory in
            let cache = ExtensionCatalogCache(directory: directory)
            let store = ExtensionSourceStore(
                settings: MemorySettingsStore(),
                catalogCache: cache,
                seedsDefaultSource: false
            )
            let refreshable = makeSource(name: "Refreshable", trusted: true, enabled: true)
            let disabled = makeSource(name: "Disabled", trusted: true, enabled: false)
            let untrusted = makeSource(name: "Untrusted", trusted: false, enabled: true)
            try store.add(refreshable)
            try store.add(disabled)
            try store.add(untrusted)

            let provider = FixtureCatalogProvider(catalog: makeCatalog())
            let viewModel = ExtensionMarketplaceViewModel(
                sourceStore: store,
                catalogService: ExtensionCatalogService(cache: cache),
                providers: try ExtensionSourceProviderRegistry(providers: [provider])
            )

            await viewModel.refreshAll()

            #expect(await provider.refreshCount == 1)
            #expect(viewModel.candidates.map(\.sourceID) == [refreshable.id])
            #expect(viewModel.state(for: disabled.id) == .disabled)
            #expect(viewModel.state(for: untrusted.id) == .untrusted)
        }
    }

    @Test
    @MainActor
    func staleCachedCatalogsRemainBrowseableAndAreReported() async throws {
        try await withTempDir { directory in
            let cache = ExtensionCatalogCache(directory: directory)
            let store = ExtensionSourceStore(
                settings: MemorySettingsStore(),
                catalogCache: cache,
                seedsDefaultSource: false
            )
            let source = makeSource(name: "Stale", trusted: true)
            try store.add(source)
            try await cache.save(
                makeCachedCatalog(fetchedAt: Date.now.addingTimeInterval(-7_200)),
                for: source.id
            )

            let viewModel = ExtensionMarketplaceViewModel(
                sourceStore: store,
                catalogService: ExtensionCatalogService(cache: cache)
            )
            await viewModel.loadCachedCatalogs()

            #expect(viewModel.candidates.count == 1)
            #expect(viewModel.sourceHealth.staleCount == 1)
            #expect(viewModel.isShowingCachedData(for: source.id))
        }
    }

    private func makeSource(
        name: String,
        trusted: Bool = true,
        enabled: Bool = true
    ) -> ExtensionSource {
        ExtensionSource(
            name: name,
            providerID: .httpsStaticIndex,
            location: URL(
                string: "https://\(name.lowercased())-\(UUID().uuidString).example/extensions.json"
            )!,
            isEnabled: enabled,
            isTrusted: trusted
        )
    }

    private func makeCachedCatalog(
        name: String = "Example",
        publisher: String = "Tests",
        fetchedAt: Date = .now
    ) -> CachedExtensionCatalog {
        let entry = ExtensionCatalogEntry(
            name: name,
            description: "Fixture extension",
            publisher: publisher,
            url: nil,
            latest: "1.0.0",
            versions: ["1.0.0": makeVersion()]
        )
        return CachedExtensionCatalog(
            catalog: ExtensionCatalog(
                schemaVersion: 1,
                extensions: ["com.example.fixture": entry]
            ),
            fetchedAt: fetchedAt,
            entityTag: "\"fixture\"",
            lastModified: nil
        )
    }

    private func makeCatalog() -> ExtensionCatalog {
        makeCachedCatalog().catalog
    }

    private func makeVersion() -> ExtensionCatalogVersion {
        ExtensionCatalogVersion(
            url: URL(string: "packages/1.0.0.zip")!,
            integrity: String(repeating: "a", count: 64),
            publishedAt: nil,
            nodal: nil
        )
    }
}

@MainActor
private final class MemorySettingsStore: ObservableObject, SettingsProviding {
    @Published var preferences = SettingsData()
    let baseURL = URL(filePath: "/tmp/extension-marketplace-view-model-tests")
}

private actor FixtureCatalogProvider: ExtensionSourceProvider {
    nonisolated let identifier = ExtensionSourceProviderID.httpsStaticIndex
    private(set) var refreshCount = 0
    private let catalog: ExtensionCatalog

    init(catalog: ExtensionCatalog) {
        self.catalog = catalog
    }

    func validate(_ source: ExtensionSource) async throws {}

    func refreshCatalog(
        for source: ExtensionSource,
        cached: CachedExtensionCatalog?
    ) async throws -> ExtensionCatalogRefresh {
        refreshCount += 1
        return ExtensionCatalogRefresh(
            catalog: catalog,
            entityTag: "\"fixture\"",
            lastModified: nil,
            notModified: false
        )
    }

    func download(
        _ package: ExtensionCatalogVersion,
        from source: ExtensionSource,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> DownloadedExtensionPackage {
        DownloadedExtensionPackage(fileURL: destination, byteCount: 0)
    }
}
