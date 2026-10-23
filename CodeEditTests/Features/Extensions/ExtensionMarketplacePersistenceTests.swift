@testable import CodeEdit
import Combine
import Foundation
import Testing

@Suite
struct ExtensionMarketplacePersistenceTests {
    @Test
    func legacyExtensionSettingsDecodeWithEmptySourceList() throws {
        let settings = try JSONDecoder().decode(
            SettingsData.ExtensionsSettings.self,
            from: Data("{}".utf8)
        )

        #expect(settings.sources.isEmpty)
        #expect(settings.syntaxPacksEnabled)
        #expect(settings.registry == nil)
    }

    @Test
    func registryConfigurationRoundTrips() throws {
        var settings = SettingsData.ExtensionsSettings()
        let configuration = ExtensionRegistryConfiguration(
            workingCopyPath: "/tmp/team-registry",
            name: "Team Registry",
            branch: "main",
            remote: "origin",
            catalogURL: "https://registry.example/extensions.json"
        )
        settings.registry = configuration

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SettingsData.ExtensionsSettings.self, from: data)

        #expect(decoded.registry == configuration)
    }

    @Test
    @MainActor
    func defaultSourceIsSeededOnceAndRemovalIsPersisted() async throws {
        let settings = MemorySettingsStore()
        let store = ExtensionSourceStore(settings: settings, seedsDefaultSource: true)

        #expect(store.sources.count == 1)
        #expect(store.sources[0].name == "Nodal IDE Extensions")
        #expect(store.sources[0].providerID == .gitRepository)
        #expect(store.sources[0].location.absoluteString == "https://github.com/nodal-ide/extensions-registry")
        #expect(store.sources[0].revision == "main")
        #expect(store.sources[0].isTrusted)
        #expect(settings.preferences.extensions.hasSeededDefaultSource)

        try await store.remove(store.sources[0].id)
        let reloaded = ExtensionSourceStore(settings: settings, seedsDefaultSource: true)

        #expect(reloaded.sources.isEmpty)
    }

    @Test
    @MainActor
    func defaultSourceSeedingDoesNotDuplicateAnExistingRegistry() {
        let settings = MemorySettingsStore()
        let existing = ExtensionSource(
            name: "Manual Registry",
            providerID: .gitRepository,
            location: URL(string: "https://github.com/nodal-ide/extensions-registry")!,
            revision: "main"
        )
        var preferences = settings.preferences
        preferences.extensions.sources = [existing]
        settings.preferences = preferences

        let store = ExtensionSourceStore(settings: settings, seedsDefaultSource: true)

        #expect(store.sources == [existing])
        #expect(settings.preferences.extensions.hasSeededDefaultSource)
    }

    @Test
    func sourceSettingsRoundTripPersistsOnlyTheKeychainReference() throws {
        var settings = SettingsData.ExtensionsSettings()
        let source = makeSource(
            name: "Private", location: "https://registry.example/extensions.json",
            credentialReference: "extension-source/github-token"
        )
        settings.sources = [source]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SettingsData.ExtensionsSettings.self, from: data)
        let json = try #require(String(bytes: data, encoding: .utf8))

        #expect(decoded.sources == [source])
        #expect(json.contains("extension-source\\/github-token") && !json.contains("secret-token"))
    }

    @Test
    @MainActor
    func sourceLifecyclePersistsTrustEnablementOrderAndRemovesCache() async throws {
        try await withTempDir { directory in
            let settings = MemorySettingsStore()
            let cache = ExtensionCatalogCache(directory: directory)
            let store = ExtensionSourceStore(
                settings: settings,
                catalogCache: cache,
                seedsDefaultSource: false
            )
            let first = makeSource(name: "First", location: "https://first.example/extensions.json")
            let second = makeSource(name: "Second", location: "https://second.example/extensions.json")

            try store.add(first)
            try store.add(second)
            try await cache.save(makeCachedCatalog(), for: first.id)
            try store.setTrusted(true, for: first.id, at: Date(timeIntervalSince1970: 100))
            try store.setEnabled(false, for: second.id)

            #expect(store.sources.map(\.id) == [first.id, second.id])
            #expect(settings.preferences.extensions.sources == store.sources)
            #expect(store.sources[0].isTrusted)
            #expect(store.sources[0].trustChangedAt == Date(timeIntervalSince1970: 100))
            #expect(!store.sources[1].isEnabled)

            try await store.remove(first.id)
            #expect(store.sources.map(\.id) == [second.id])
            #expect(settings.preferences.extensions.sources == store.sources)
            #expect(try await cache.load(for: first.id) == nil)
        }
    }

    @Test
    func cachedCatalogPersistsAtomicallyAndEnforcesSizeLimit() async throws {
        try await withTempDir { directory in
            let cache = ExtensionCatalogCache(directory: directory)
            let source = ExtensionSourceID()
            let expected = makeCachedCatalog()

            try await cache.save(expected, for: source)

            #expect(try await cache.load(for: source) == expected)
            let constrained = ExtensionCatalogCache(directory: directory, maximumBytes: 32)
            var rejectedOversizedCatalog = false
            do {
                try await constrained.save(expected, for: ExtensionSourceID())
            } catch ExtensionCatalogCacheError.sizeLimitExceeded {
                rejectedOversizedCatalog = true
            }
            #expect(rejectedOversizedCatalog)
        }
    }

    @Test
    func refreshUsesTTLAndForcedRefreshBypassesIt() async throws {
        try await withTempDir { directory in
            let cache = ExtensionCatalogCache(directory: directory)
            let provider = CountingCatalogProvider(catalog: makeCachedCatalog().catalog)
            let registry = try ExtensionSourceProviderRegistry(providers: [provider])
            let service = ExtensionCatalogService(cache: cache)
            let source = makeSource(name: "Trusted", location: "https://registry.example/index.json", trusted: true)
            let now = Date(timeIntervalSince1970: 10_000)

            let initial = await service.refresh(source: source, providers: registry, now: now)
            let withinTTL = await service.refresh(
                source: source,
                providers: registry,
                now: now.addingTimeInterval(1_800)
            )
            let forced = await service.refresh(
                source: source,
                providers: registry,
                force: true,
                now: now.addingTimeInterval(1_801)
            )

            #expect(initial == .fresh(fetchedAt: now, extensionCount: 1))
            #expect(withinTTL == initial)
            #expect(forced == .fresh(fetchedAt: now.addingTimeInterval(1_801), extensionCount: 1))
            #expect(await provider.refreshCount == 2)
        }
    }

    @Test
    func conditionalNotModifiedRefreshRetainsCatalogAndValidators() async throws {
        try await withTempDir { directory in
            let now = Date(timeIntervalSince1970: 10_000)
            let source = makeSource(name: "Trusted", location: "https://registry.example/index.json", trusted: true)
            let previous = makeCachedCatalog(fetchedAt: now.addingTimeInterval(-7_200))
            let cache = ExtensionCatalogCache(directory: directory)
            try await cache.save(previous, for: source.id)
            let provider = CountingCatalogProvider(catalog: previous.catalog, notModified: true)
            let registry = try ExtensionSourceProviderRegistry(providers: [provider])
            let service = ExtensionCatalogService(cache: cache)

            let state = await service.refresh(source: source, providers: registry, now: now)
            let updatedCache = try await cache.load(for: source.id)

            #expect(state == .fresh(fetchedAt: now, extensionCount: 1))
            #expect(updatedCache?.catalog == previous.catalog)
            #expect(updatedCache?.entityTag == previous.entityTag)
            #expect(updatedCache?.fetchedAt == now)
            #expect(await provider.lastReceivedEntityTag == previous.entityTag)
        }
    }

    @Test
    func concurrentRefreshesForOneSourceAreCoalesced() async throws {
        try await withTempDir { directory in
            let provider = CountingCatalogProvider(catalog: makeCachedCatalog().catalog, delay: .milliseconds(40))
            let registry = try ExtensionSourceProviderRegistry(providers: [provider])
            let service = ExtensionCatalogService(cache: ExtensionCatalogCache(directory: directory))
            let source = makeSource(name: "Trusted", location: "https://registry.example/index.json", trusted: true)

            async let first = service.refresh(source: source, providers: registry)
            async let second = service.refresh(source: source, providers: registry)
            async let third = service.refresh(source: source, providers: registry)
            let states = await [first, second, third]

            #expect(states.allSatisfy {
                if case .fresh = $0 { return true }
                return false
            })
            #expect(await provider.refreshCount == 1)
        }
    }

    @Test
    func untrustedSourceNeverCallsProviderAndOfflineFailureKeepsStaleCatalog() async throws {
        try await withTempDir { directory in
            let sourceID = ExtensionSourceID()
            let cached = makeCachedCatalog(fetchedAt: Date(timeIntervalSince1970: 100))
            let cache = ExtensionCatalogCache(directory: directory)
            try await cache.save(cached, for: sourceID)
            let provider = CountingCatalogProvider(catalog: cached.catalog, failsOffline: true)
            let registry = try ExtensionSourceProviderRegistry(providers: [provider])
            let service = ExtensionCatalogService(cache: cache)
            let untrusted = makeSource(
                id: sourceID,
                name: "Untrusted",
                location: "https://registry.example/index.json",
                trusted: false
            )
            let trusted = makeSource(
                id: sourceID,
                name: "Trusted",
                location: "https://registry.example/index.json",
                trusted: true
            )

            #expect(await service.refresh(source: untrusted, providers: registry) == .untrusted)
            #expect(await provider.refreshCount == 0)
            #expect(await service.refresh(source: trusted, providers: registry, force: true) ==
                .stale(fetchedAt: cached.fetchedAt, failure: .unavailable))
            #expect(await provider.refreshCount == 1)
            #expect(try await service.cachedCatalog(for: sourceID) == cached)
        }
    }

    private func makeCachedCatalog(fetchedAt: Date = Date(timeIntervalSince1970: 1)) -> CachedExtensionCatalog {
        let package = ExtensionCatalogVersion(
            url: URL(string: "0.1.0.zip")!,
            integrity: String(repeating: "a", count: 64),
            publishedAt: nil,
            nodal: nil
        )
        let entry = ExtensionCatalogEntry(
            name: "Example",
            description: "Example package",
            publisher: "Tests",
            url: nil,
            latest: "0.1.0",
            versions: ["0.1.0": package]
        )
        return CachedExtensionCatalog(
            catalog: ExtensionCatalog(schemaVersion: 1, extensions: ["com.example.pack": entry]),
            fetchedAt: fetchedAt,
            entityTag: "\"revision-1\"",
            lastModified: nil
        )
    }

}

private extension ExtensionMarketplacePersistenceTests {
    private func makeSource(
        id: ExtensionSourceID = .init(),
        name: String,
        location: String,
        trusted: Bool = false,
        credentialReference: String? = nil
    ) -> ExtensionSource {
        ExtensionSource(
            id: id,
            name: name,
            providerID: .httpsStaticIndex,
            location: URL(string: location)!,
            isTrusted: trusted,
            credentialReference: credentialReference
        )
    }
}

@MainActor
private final class MemorySettingsStore: ObservableObject, SettingsProviding {
    @Published var preferences = SettingsData()
    let baseURL = URL(filePath: "/tmp/extension-settings-tests")
}

private actor CountingCatalogProvider: ExtensionSourceProvider {
    let catalog: ExtensionCatalog
    let delay: Duration
    let failsOffline: Bool
    let notModified: Bool
    private(set) var refreshCount = 0
    private(set) var lastReceivedEntityTag: String?
    nonisolated let identifier = ExtensionSourceProviderID.httpsStaticIndex

    init(
        catalog: ExtensionCatalog,
        delay: Duration = .zero,
        failsOffline: Bool = false,
        notModified: Bool = false
    ) {
        self.catalog = catalog
        self.delay = delay
        self.failsOffline = failsOffline
        self.notModified = notModified
    }

    func validate(_ source: ExtensionSource) async throws {}

    func refreshCatalog(
        for source: ExtensionSource,
        cached: CachedExtensionCatalog?
    ) async throws -> ExtensionCatalogRefresh {
        refreshCount += 1
        lastReceivedEntityTag = cached?.entityTag
        if delay > .zero { try await Task.sleep(for: delay) }
        if failsOffline { throw ExtensionSourceProviderError.transport("offline") }
        return ExtensionCatalogRefresh(
            catalog: catalog,
            entityTag: notModified ? nil : "\"revision-1\"",
            lastModified: nil,
            notModified: notModified
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
