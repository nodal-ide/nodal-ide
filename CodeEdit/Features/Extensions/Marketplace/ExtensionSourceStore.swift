import Foundation
import Combine

@MainActor
final class ExtensionSourceStore: ObservableObject {
    static let shared = ExtensionSourceStore(settings: AppServices.settings)

    @Published private(set) var sources: [ExtensionSource]

    private let settings: any SettingsProviding
    private let catalogCache: ExtensionCatalogCache
    private static let defaultSource = ExtensionSource(
        name: "Nodal IDE Extensions",
        providerID: .httpsStaticIndex,
        location: URL(
            string: "https://raw.githubusercontent.com/nodal-ide/extensions-registry/refs/heads/main/extensions.json"
        )!,
        isEnabled: true,
        isTrusted: false
    )

    init(
        settings: any SettingsProviding,
        catalogCache: ExtensionCatalogCache = ExtensionCatalogCache()
    ) {
        self.settings = settings
        self.catalogCache = catalogCache

            var preferences = settings.preferences
            var extensions = preferences.extensions

            if !extensions.hasSeededDefaultSource {
                extensions.sources.append(Self.defaultSource)
                extensions.hasSeededDefaultSource = true
                preferences.extensions = extensions
                settings.preferences = preferences
            }

            self.sources = settings.preferences.extensions.sources
    }

    func reload() {
        sources = settings.preferences.extensions.sources
    }

    func add(_ source: ExtensionSource) throws {
        try updateSources { $0.append(source) }
    }

    func update(_ source: ExtensionSource) throws {
        try updateSources { sources in
            guard let index = sources.firstIndex(where: { $0.id == source.id }) else {
                throw ExtensionSourceStoreError.sourceNotFound(source.id)
            }
            sources[index] = source
        }
    }

    func remove(_ sourceID: ExtensionSourceID) async throws {
        try updateSources { sources in
            guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
                throw ExtensionSourceStoreError.sourceNotFound(sourceID)
            }
            sources.remove(at: index)
        }
        try? await catalogCache.remove(for: sourceID)
    }

    func setEnabled(_ isEnabled: Bool, for sourceID: ExtensionSourceID) throws {
        try updateSource(sourceID) { $0.isEnabled = isEnabled }
    }

    func setTrusted(_ isTrusted: Bool, for sourceID: ExtensionSourceID, at date: Date = .now) throws {
        try updateSource(sourceID) {
            $0.isTrusted = isTrusted
            $0.trustChangedAt = date
        }
    }

    private func updateSource(
        _ sourceID: ExtensionSourceID,
        transform: (inout ExtensionSource) -> Void
    ) throws {
        try updateSources { sources in
            guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
                throw ExtensionSourceStoreError.sourceNotFound(sourceID)
            }
            transform(&sources[index])
        }
    }

    private func updateSources(_ transform: (inout [ExtensionSource]) throws -> Void) throws {
        var updated = sources
        try transform(&updated)
        _ = try ExtensionSourceCollection(sources: updated)
        var preferences = settings.preferences
        preferences.extensions.sources = updated
        settings.preferences = preferences
        sources = updated
    }
}

enum ExtensionSourceStoreError: Error {
    case sourceNotFound(ExtensionSourceID)
}
