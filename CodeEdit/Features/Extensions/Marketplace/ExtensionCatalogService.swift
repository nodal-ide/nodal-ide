import Foundation

enum ExtensionCatalogFailure: Equatable, Sendable {
    case invalidCatalog
    case unavailable
    case providerUnavailable
    case cacheUnavailable
}

enum ExtensionSourceCatalogState: Equatable, Sendable {
    case idle
    case loading(cachedAt: Date?)
    case fresh(fetchedAt: Date, extensionCount: Int)
    case stale(fetchedAt: Date, failure: ExtensionCatalogFailure)
    case offline(cachedAt: Date?)
    case invalid(ExtensionCatalogFailure)
    case untrusted
    case disabled
}

actor ExtensionCatalogService {
    static let defaultTimeToLive: TimeInterval = 3_600

    private struct InFlightRefresh {
        let token: UUID
        let fingerprint: SourceFingerprint
        let task: Task<ExtensionSourceCatalogState, Never>
    }

    private let cache: ExtensionCatalogCache
    private var states: [ExtensionSourceID: ExtensionSourceCatalogState] = [:]
    private var inFlight: [ExtensionSourceID: InFlightRefresh] = [:]

    init(cache: ExtensionCatalogCache = ExtensionCatalogCache()) {
        self.cache = cache
    }

    func state(for sourceID: ExtensionSourceID) -> ExtensionSourceCatalogState {
        states[sourceID] ?? .idle
    }

    func cachedCatalog(for sourceID: ExtensionSourceID) async throws -> CachedExtensionCatalog? {
        try await cache.load(for: sourceID)
    }

    func removeSource(_ sourceID: ExtensionSourceID) async throws {
        inFlight[sourceID]?.task.cancel()
        inFlight.removeValue(forKey: sourceID)
        states.removeValue(forKey: sourceID)
        try await cache.remove(for: sourceID)
    }

    func refresh(
        source: ExtensionSource,
        providers: ExtensionSourceProviderRegistry,
        force: Bool = false,
        now: Date = .now
    ) async -> ExtensionSourceCatalogState {
        guard (try? ExtensionSourceCollection(sources: [source])) != nil else {
            states[source.id] = .invalid(.invalidCatalog)
            return .invalid(.invalidCatalog)
        }
        guard source.isEnabled else {
            states[source.id] = .disabled
            return .disabled
        }
        guard source.isTrusted else {
            states[source.id] = .untrusted
            return .untrusted
        }

        let cachedResult: Result<CachedExtensionCatalog?, ExtensionCatalogCacheError>
        do {
            cachedResult = .success(try await cache.load(for: source.id))
        } catch let error as ExtensionCatalogCacheError {
            cachedResult = .failure(error)
        } catch {
            cachedResult = .failure(.invalidCache)
        }

        let cached = try? cachedResult.get()
        if !force, let cached, now.timeIntervalSince(cached.fetchedAt) < timeToLive(for: source) {
            let fresh = Self.freshState(for: cached)
            states[source.id] = fresh
            return fresh
        }

        if let existing = inFlight[source.id], existing.fingerprint == SourceFingerprint(source) {
            return await existing.task.value
        }
        inFlight[source.id]?.task.cancel()

        let token = UUID()
        let fingerprint = SourceFingerprint(source)
        states[source.id] = .loading(cachedAt: cached?.fetchedAt)
        let cache = self.cache
        let previousCache = cached
        let task = Task.detached(priority: .utility) { () -> ExtensionSourceCatalogState in
            do {
                let provider = try providers.provider(for: source)
                let update = try await provider.refreshCatalog(for: source, cached: previousCache)
                let catalog: ExtensionCatalog
                if update.notModified {
                    guard let previousCache else { return .invalid(.invalidCatalog) }
                    catalog = previousCache.catalog
                } else {
                    catalog = update.catalog
                }
                try ExtensionCatalogValidator.validate(catalog)
                let refreshed = CachedExtensionCatalog(
                    catalog: catalog,
                    fetchedAt: now,
                    entityTag: update.entityTag ?? previousCache?.entityTag,
                    lastModified: update.lastModified ?? previousCache?.lastModified
                )
                try await cache.save(refreshed, for: source.id)
                return Self.freshState(for: refreshed)
            } catch is CancellationError {
                return Self.fallbackState(cache: previousCache, failure: .unavailable)
            } catch is ExtensionCatalogValidationError {
                return Self.fallbackState(cache: previousCache, failure: .invalidCatalog)
            } catch let error as ExtensionSourceProviderError {
                let failure: ExtensionCatalogFailure = switch error {
                case .unsupportedProvider: .providerUnavailable
                case .transport, .cancelled: .unavailable
                case .invalidConfiguration, .invalidResponse, .responseTooLarge,
                     .unsupportedRedirect, .integrityMismatch:
                    .invalidCatalog
                case .duplicateProvider: .providerUnavailable
                }
                return Self.fallbackState(cache: previousCache, failure: failure)
            } catch is ExtensionCatalogCacheError {
                return Self.fallbackState(cache: previousCache, failure: .cacheUnavailable)
            } catch {
                return Self.fallbackState(cache: previousCache, failure: .unavailable)
            }
        }
        inFlight[source.id] = InFlightRefresh(token: token, fingerprint: fingerprint, task: task)
        let result = await task.value
        if inFlight[source.id]?.token == token {
            states[source.id] = result
            inFlight.removeValue(forKey: source.id)
        }
        return result
    }

    private func timeToLive(for source: ExtensionSource) -> TimeInterval {
        source.refreshInterval ?? Self.defaultTimeToLive
    }

    private static func freshState(for cache: CachedExtensionCatalog) -> ExtensionSourceCatalogState {
        .fresh(fetchedAt: cache.fetchedAt, extensionCount: cache.catalog.extensions.count)
    }

    private static func fallbackState(
        cache: CachedExtensionCatalog?,
        failure: ExtensionCatalogFailure
    ) -> ExtensionSourceCatalogState {
        if let cache {
            return .stale(fetchedAt: cache.fetchedAt, failure: failure)
        }
        if failure == .invalidCatalog || failure == .providerUnavailable || failure == .cacheUnavailable {
            return .invalid(failure)
        }
        return .offline(cachedAt: nil)
    }
}

private struct SourceFingerprint: Equatable, Sendable {
    let providerID: ExtensionSourceProviderID
    let location: URL
    let credentialReference: String?

    init(_ source: ExtensionSource) {
        self.providerID = source.providerID
        self.location = source.location
        self.credentialReference = source.credentialReference
    }
}
