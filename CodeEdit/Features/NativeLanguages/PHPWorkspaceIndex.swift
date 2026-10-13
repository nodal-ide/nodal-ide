//
//  PHPWorkspaceIndex.swift
//  CodeEdit
//
//  Native PHP language support: project symbol index per workspace.
//

import Foundation
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
            indexer.buildIndex(at: root)
        }
        return symbolIndex
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
}