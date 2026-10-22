import Foundation

struct CachedExtensionCatalog: Codable, Hashable, Sendable {
    let catalog: ExtensionCatalog
    let fetchedAt: Date
    let entityTag: String?
    let lastModified: String?
}

struct ExtensionCatalogRefresh: Sendable {
    let catalog: ExtensionCatalog
    let entityTag: String?
    let lastModified: String?
    let notModified: Bool
}

struct DownloadedExtensionPackage: Sendable {
    let fileURL: URL
    let byteCount: Int64
}

enum ExtensionSourceProviderError: Error, Equatable {
    case unsupportedProvider(ExtensionSourceProviderID)
    case duplicateProvider(ExtensionSourceProviderID)
    case invalidConfiguration(String)
    case invalidResponse
    case responseTooLarge
    case unsupportedRedirect
    case integrityMismatch
    case transport(String)
    case cancelled
}

protocol ExtensionSourceProvider: Sendable {
    var identifier: ExtensionSourceProviderID { get }

    func validate(_ source: ExtensionSource) async throws

    func refreshCatalog(
        for source: ExtensionSource,
        cached: CachedExtensionCatalog?
    ) async throws -> ExtensionCatalogRefresh

    func download(
        _ package: ExtensionCatalogVersion,
        from source: ExtensionSource,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> DownloadedExtensionPackage
}

struct ExtensionSourceProviderRegistry: Sendable {
    private let providers: [ExtensionSourceProviderID: any ExtensionSourceProvider]

    init(providers: [any ExtensionSourceProvider]) throws {
        var indexed: [ExtensionSourceProviderID: any ExtensionSourceProvider] = [:]
        for provider in providers {
            guard indexed[provider.identifier] == nil else {
                throw ExtensionSourceProviderError.duplicateProvider(provider.identifier)
            }
            indexed[provider.identifier] = provider
        }
        self.providers = indexed
    }

    func provider(for source: ExtensionSource) throws -> any ExtensionSourceProvider {
        guard let provider = providers[source.providerID] else {
            throw ExtensionSourceProviderError.unsupportedProvider(source.providerID)
        }
        return provider
    }
}
