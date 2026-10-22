import Foundation

actor ExtensionCatalogCache {
    static let defaultMaximumBytes = 4 * 1_024 * 1_024

    private let directory: URL
    private let maximumBytes: Int
    private let fileManager: FileManager

    init(
        directory: URL = ExtensionCatalogCache.defaultDirectory,
        maximumBytes: Int = ExtensionCatalogCache.defaultMaximumBytes,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.maximumBytes = max(1, maximumBytes)
        self.fileManager = fileManager
    }

    func load(for sourceID: ExtensionSourceID) throws -> CachedExtensionCatalog? {
        let file = cacheFile(for: sourceID)
        guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: file.path(percentEncoded: false))
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.uint64Value <= UInt64(maximumBytes) else {
            throw ExtensionCatalogCacheError.sizeLimitExceeded
        }
        do {
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode(CachedExtensionCatalog.self, from: data)
            try ExtensionCatalogValidator.validate(cached.catalog)
            return cached
        } catch let error as ExtensionCatalogValidationError {
            throw ExtensionCatalogCacheError.invalidCatalog(error)
        } catch let error as ExtensionCatalogCacheError {
            throw error
        } catch {
            throw ExtensionCatalogCacheError.invalidCache
        }
    }

    func save(_ catalog: CachedExtensionCatalog, for sourceID: ExtensionSourceID) throws {
        try ExtensionCatalogValidator.validate(catalog.catalog)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(catalog)
        guard data.count <= maximumBytes else { throw ExtensionCatalogCacheError.sizeLimitExceeded }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: cacheFile(for: sourceID), options: .atomic)
    }

    func remove(for sourceID: ExtensionSourceID) throws {
        let file = cacheFile(for: sourceID)
        guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: file)
    }

    private func cacheFile(for sourceID: ExtensionSourceID) -> URL {
        directory.appending(path: "\(sourceID.rawValue.uuidString).json", directoryHint: .notDirectory)
    }

    private static var defaultDirectory: URL {
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return cacheRoot.appending(path: "Nodal/ExtensionCatalogs", directoryHint: .isDirectory)
    }
}

enum ExtensionCatalogCacheError: Error, Equatable {
    case sizeLimitExceeded
    case invalidCache
    case invalidCatalog(ExtensionCatalogValidationError)
}
