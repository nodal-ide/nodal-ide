import Foundation

/// Where an installed package came from. Persisted next to the pack so removing a source never
/// loses the installed package's origin.
struct ExtensionProvenance: Codable, Hashable, Sendable {
    static let fileName = ".nodal-provenance.json"

    let sourceID: ExtensionSourceID
    let sourceName: String
    let providerID: ExtensionSourceProviderID
    let sourceLocation: URL
    let extensionID: String
    let version: String
    let integrity: String
    let installedAt: Date

    init(
        source: ExtensionSource,
        extensionID: String,
        version: String,
        integrity: String,
        installedAt: Date = .now
    ) {
        self.sourceID = source.id
        self.sourceName = source.name
        self.providerID = source.providerID
        self.sourceLocation = source.location
        self.extensionID = extensionID
        self.version = version
        self.integrity = integrity
        self.installedAt = Date(
            timeIntervalSince1970: installedAt.timeIntervalSince1970.rounded(.down)
        )
    }

    static func load(from packRoot: URL) -> ExtensionProvenance? {
        let file = packRoot.appending(path: fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ExtensionProvenance.self, from: data)
    }

    func write(to packRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: packRoot.appending(path: Self.fileName), options: .atomic)
    }

    static func remove(from packRoot: URL) {
        try? FileManager.default.removeItem(at: packRoot.appending(path: fileName))
    }
}

struct ExtensionPackageIdentity: Hashable, Sendable {
    let extensionID: String
    let version: String?
}
