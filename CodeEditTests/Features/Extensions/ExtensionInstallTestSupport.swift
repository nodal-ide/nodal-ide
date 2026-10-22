import Foundation
import Testing
import CodeEditLang
@testable import CodeEdit

enum ExtensionInstallFixtures {
    static func makePackage(
        in parent: URL,
        id: String = "com.example.demo",
        version: String = "1.0.0",
        files: [String: String] = ["README.md": "Demo"]
    ) throws -> URL {
        let root = parent.appending(path: "package-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = LanguageExtensionManifest(
            schemaVersion: 2,
            id: id,
            name: "Demo",
            version: version,
            type: "languagePack",
            engines: .init(codeedit: ">=0.1.0")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: root.appending(path: "extension.json"))
        for (path, contents) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    static func makeSource(
        id: ExtensionSourceID = ExtensionSourceID(),
        name: String = "Test Registry",
        providerID: ExtensionSourceProviderID = .httpsStaticIndex,
        trusted: Bool = true
    ) -> ExtensionSource {
        ExtensionSource(
            id: id,
            name: name,
            providerID: providerID,
            location: URL(string: "https://registry.example/extensions.json")!,
            isEnabled: true,
            isTrusted: trusted
        )
    }

    static func makeCandidate(
        source: ExtensionSource,
        extensionID: String = "com.example.demo",
        version: String = "1.0.0"
    ) -> ExtensionCatalogCandidate {
        let package = ExtensionCatalogVersion(
            url: URL(string: "packages/demo-\(version).zip")!,
            integrity: String(repeating: "a", count: 64),
            publishedAt: nil,
            nodal: nil
        )
        let entry = ExtensionCatalogEntry(
            name: "Demo",
            description: "Demo extension",
            publisher: "Example",
            url: nil,
            latest: version,
            versions: [version: package]
        )
        return ExtensionCatalogCandidate(
            sourceID: source.id,
            extensionID: extensionID,
            version: version,
            entry: entry,
            package: package
        )
    }

    static func makeArchive(_ entries: [ZipFixture.Entry], at url: URL) throws {
        try ZipFixture.make(entries).write(to: url, options: .atomic)
    }

    static func manifestJSON(id: String = "com.example.demo", version: String = "1.0.0") throws -> String {
        let manifest = LanguageExtensionManifest(
            schemaVersion: 2,
            id: id,
            name: "Demo",
            version: version,
            type: "languagePack",
            engines: .init(codeedit: ">=0.1.0")
        )
        let data = try JSONEncoder().encode(manifest)
        return try #require(String(bytes: data, encoding: .utf8))
    }

    static func withTempDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EM5Tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    static func withTempDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EM5Tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }
}

actor LocalPackageProvider: ExtensionSourceProvider {
    nonisolated let identifier: ExtensionSourceProviderID
    private let archiveURL: URL
    private let delay: Duration
    private(set) var downloadCount = 0

    init(
        identifier: ExtensionSourceProviderID = .httpsStaticIndex,
        archiveURL: URL,
        delay: Duration = .zero
    ) {
        self.identifier = identifier
        self.archiveURL = archiveURL
        self.delay = delay
    }

    func validate(_ source: ExtensionSource) async throws {}

    func refreshCatalog(
        for source: ExtensionSource,
        cached: CachedExtensionCatalog?
    ) async throws -> ExtensionCatalogRefresh {
        throw ExtensionSourceProviderError.invalidResponse
    }

    func download(
        _ package: ExtensionCatalogVersion,
        from source: ExtensionSource,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> DownloadedExtensionPackage {
        downloadCount += 1
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        try FileManager.default.copyItem(at: archiveURL, to: destination)
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        progress(size, size)
        return DownloadedExtensionPackage(fileURL: destination, byteCount: size)
    }
}

enum ZipFixture {
    struct Entry {
        let path: String
        let data: Data
        let mode: UInt32

        static func file(_ path: String, _ contents: String) -> Entry {
            Entry(path: path, data: Data(contents.utf8), mode: 0o100644)
        }

        static func directory(_ path: String) -> Entry {
            Entry(path: path, data: Data(), mode: 0o040755)
        }

        static func symlink(_ path: String, target: String) -> Entry {
            Entry(path: path, data: Data(target.utf8), mode: 0o120777)
        }
    }

    static func make(_ entries: [Entry]) -> Data {
        var archive = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let checksum = crc32(entry.data)
            let offset = UInt32(archive.count)
            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(checksum)
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt16(name.count))
            archive.appendLE(UInt16(0))
            archive.append(name)
            archive.append(entry.data)

            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(0x031E))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(checksum)
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(entry.mode << 16)
            central.appendLE(offset)
            central.append(name)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(central.count))
        archive.appendLE(centralOffset)
        archive.appendLE(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
