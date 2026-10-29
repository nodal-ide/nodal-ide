//
//  ChangeRibbonService.swift
//  CodeEdit
//

import Foundation
import CodeEditSourceEditor

/// Loads and caches the uncommitted line changes shown in an editor's gutter ribbon.
///
/// The cache key is cheap to compute and changes whenever the ribbon could have changed: the file's modification
/// date and size, plus its git status. Saved edits, commits, staging, resets and branch switches all move the key, so
/// an unchanged file costs no process at all. Only a single caller (one editor) requests a URL at a time, so
/// concurrent requests for the same file are not coalesced.
@MainActor
final class ChangeRibbonService {
    private struct Signature: Equatable {
        let modified: Date?
        let size: Int
        let status: String
    }

    private struct Entry {
        let signature: Signature
        let changes: [LineChange]
    }

    /// Cache bound; a workspace rarely has more editors than this open at once.
    private static let cacheLimit = 64

    private let coordinatorProvider: () -> SourceControlCoordinator?
    private var cache: [URL: Entry] = [:]

    init(coordinatorProvider: @escaping () -> SourceControlCoordinator?) {
        self.coordinatorProvider = coordinatorProvider
    }

    func changes(for url: URL) async -> [LineChange] {
        let url = url.standardizedFileURL
        guard let repository = coordinatorProvider()?.repoForFile(url) else { return [] }

        let file = repository.changedFiles.first { $0.fileURL.standardizedFileURL == url }
        let signature = signature(for: url, status: file?.signature ?? "-")
        if let entry = cache[url], entry.signature == signature {
            return entry.changes
        }

        let changes = await repository.lineChanges(for: url, untracked: file?.anyStatus() == .untracked)
        if cache.count >= Self.cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[url] = Entry(signature: signature, changes: changes)
        return changes
    }

    private func signature(for url: URL, status: String) -> Signature {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return Signature(
            modified: attributes?[.modificationDate] as? Date,
            size: (attributes?[.size] as? NSNumber)?.intValue ?? 0,
            status: status
        )
    }
}

private extension GitChangedFile {
    /// Both statuses, so staging or unstaging a file invalidates the cache.
    var signature: String {
        status.rawValue + stagedStatus.rawValue
    }
}
