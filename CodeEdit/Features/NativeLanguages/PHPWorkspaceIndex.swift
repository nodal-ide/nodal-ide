//
//  PHPWorkspaceIndex.swift
//  CodeEdit
//
//  Native PHP language support: project symbol index per workspace.
//

import Foundation
import CodeEditSourceEditor
import CodeEditLang
import CodeEditLangPHP

/// Owns one `SymbolIndex` per workspace root and builds it lazily in the background.
///
/// This is the app-side entry point for the native PHP provider. The index stores only
/// lightweight symbol records (no file contents) and is thread-safe, so building it off
/// the main thread is safe while the editor keeps rendering.
final class PHPWorkspaceIndex: @unchecked Sendable {
    static let shared = PHPWorkspaceIndex()

    private let lock = NSLock()
    private var indexes: [String: SymbolIndex] = [:]
    private var indexers: [String: PHPProjectIndexer] = [:]
    private var providers: [URL: PHPProvider] = [:]

    /// All workspace roots that currently have an index (used when reloading extensions globally).
    var allRoots: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return indexes.keys.map { URL(fileURLWithPath: $0) }
    }

    /// Returns (creating + building if needed) the symbol index for a workspace root.
    func index(for root: URL) -> SymbolIndex {
        let key = root.path(percentEncoded: false)

        lock.lock()
        if let existing = indexes[key] {
            lock.unlock()
            return existing
        }
        let symbolIndex = SymbolIndex()
        let indexer = PHPProjectIndexer(index: symbolIndex)
        indexes[key] = symbolIndex
        indexers[key] = indexer
        lock.unlock()

        Task.detached(priority: .utility) {
            await indexer.buildIndex(at: root)
        }
        return symbolIndex
    }

    /// Returns a cached PHP provider for a file, stable across SwiftUI view recreations.
    func provider(
        for file: URL,
        root: URL,
        openLink: @escaping (JumpToDefinitionLink) -> Void
    ) -> PHPProvider {
        // Resolve the index first (it takes the lock internally) to avoid nested locking.
        let symbolIndex = index(for: root)

        lock.lock()
        defer { lock.unlock() }
        if let existing = providers[file] {
            return existing
        }
        let provider = PHPProvider(fileURL: file, index: symbolIndex, openLink: openLink)
        providers[file] = provider
        return provider
    }

    /// Re-indexes a single file (call after saving).
    func refresh(file: URL) {
        let path = file.path(percentEncoded: false)
        lock.lock()
        let candidates = indexers
        lock.unlock()
        for (root, indexer) in candidates where path.hasPrefix(root) {
            indexer.refreshFile(at: file)
        }
    }

    /// Re-indexes a single file from in-memory content (debounced while editing), so the
    /// workspace index stays fresh without waiting for a save.
    func refreshFromSource(file: URL, source: String) {
        let path = file.path(percentEncoded: false)
        lock.lock()
        let candidates = indexers
        lock.unlock()
        for (root, indexer) in candidates where path.hasPrefix(root) {
            Task.detached(priority: .utility) {
                let info = await PHPParseCache.shared.infoAsync(for: file, source: source)
                indexer.replace(file: file, with: info.symbols)
            }
        }
    }
}
