import Foundation
import ZIPFoundation

/// Extracts a marketplace archive into a fresh staging directory.
///
/// ZIP validation is intentionally stricter than the archive reader: paths must be relative and
/// unique, symlinks are rejected, and compressed content is bounded before anything is written.
struct ExtensionArchiveExtractor {
    let maximumEntries: Int
    let maximumEntryBytes: UInt64
    let maximumExpandedBytes: UInt64
    let maximumPathBytes: Int

    init(
        maximumEntries: Int = 20_000,
        maximumEntryBytes: UInt64 = 512 * 1_024 * 1_024,
        maximumExpandedBytes: UInt64 = 1_024 * 1_024 * 1_024,
        maximumPathBytes: Int = 1_024
    ) {
        self.maximumEntries = maximumEntries
        self.maximumEntryBytes = maximumEntryBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.maximumPathBytes = maximumPathBytes
    }

    func extract(
        archiveAt archiveURL: URL,
        to destination: URL,
        progress: (Double) -> Void = { _ in }
    ) throws -> URL {
        try Task.checkCancellation()
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let entries = try validatedEntries(in: archive)
        let expectedBytes = entries.reduce(into: UInt64(0)) { $0 += $1.0.uncompressedSize }
        let progressState = Progress(totalUnitCount: Int64(max(1, expectedBytes)))
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for (entry, relativePath) in entries {
            try Task.checkCancellation()
            let target = destination.appending(path: relativePath)
            guard isContained(target, in: destination) else {
                throw ExtensionArchiveError.unsafePath(entry.path)
            }
            if entry.type == .directory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                _ = try archive.extract(entry, to: target, progress: progressState)
            }
            progress(Double(progressState.completedUnitCount) / Double(progressState.totalUnitCount))
        }

        try Task.checkCancellation()
        try rejectSymbolicLinks(in: destination)
        return try packRoot(in: destination)
    }

    private func validatedEntries(in archive: Archive) throws -> [(Entry, String)] {
        var entries: [(Entry, String)] = []
        var seenPaths = Set<String>()
        var expandedBytes: UInt64 = 0

        for entry in archive {
            guard entries.count < maximumEntries else {
                throw ExtensionArchiveError.tooManyEntries
            }
            let path = try normalizedPath(entry.path)
            guard seenPaths.insert(path.lowercased()).inserted else {
                throw ExtensionArchiveError.duplicatePath(entry.path)
            }
            guard entry.type != .symlink else {
                throw ExtensionArchiveError.symbolicLink(entry.path)
            }
            guard entry.uncompressedSize <= maximumEntryBytes else {
                throw ExtensionArchiveError.entryTooLarge(entry.path)
            }
            let (total, overflow) = expandedBytes.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, total <= maximumExpandedBytes else {
                throw ExtensionArchiveError.expandedSizeExceeded
            }
            expandedBytes = total
            entries.append((entry, path))
        }
        return entries
    }

    private func normalizedPath(_ rawPath: String) throws -> String {
        guard !rawPath.isEmpty,
              rawPath.utf8.count <= maximumPathBytes,
              !rawPath.hasPrefix("/"),
              !rawPath.contains("\\"),
              !rawPath.contains("\0") else {
            throw ExtensionArchiveError.unsafePath(rawPath)
        }
        let withoutTrailingSlash = rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath
        let components = withoutTrailingSlash.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ExtensionArchiveError.unsafePath(rawPath)
        }
        return components.joined(separator: "/")
    }

    private func packRoot(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let direct = directory.appending(path: "extension.json")
        if fileManager.fileExists(atPath: direct.path(percentEncoded: false)) {
            return directory
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var candidates: [URL] = []
        for child in children {
            let manifest = child.appending(path: "extension.json")
            if fileManager.fileExists(atPath: manifest.path(percentEncoded: false)) {
                candidates.append(child)
            }
        }
        guard candidates.count == 1, let root = candidates.first else {
            throw ExtensionArchiveError.missingManifest
        }
        return root
    }

    private func rejectSymbolicLinks(in root: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true || !isContained(url, in: root) {
                throw ExtensionArchiveError.symbolicLink(url.lastPathComponent)
            }
        }
    }

    private func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }
}

enum ExtensionArchiveError: LocalizedError {
    case unsafePath(String)
    case symbolicLink(String)
    case duplicatePath(String)
    case entryTooLarge(String)
    case expandedSizeExceeded
    case tooManyEntries
    case missingManifest

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            return "The archive contains an unsafe path: \(path)."
        case .symbolicLink(let path):
            return "The archive contains a symbolic link: \(path)."
        case .duplicatePath(let path):
            return "The archive contains a duplicate path: \(path)."
        case .entryTooLarge(let path):
            return "The archive entry is too large: \(path)."
        case .expandedSizeExceeded:
            return "The expanded archive is too large to install."
        case .tooManyEntries:
            return "The archive contains too many files to install."
        case .missingManifest:
            return "The archive has no single extension.json package root."
        }
    }
}
