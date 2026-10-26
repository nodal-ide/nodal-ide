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
    private var pendingDiagnostics: [URL: [PHPDiagnostic]] = [:]
    private var flushScheduled = false

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
        // Deliver project-wide diagnostics to the Problems panel as files are indexed.
        indexer.diagnosticsConfig = Self.currentDiagnosticsConfig()
        indexer.onDiagnostics = { [weak self] url, issues in
            self?.enqueueDiagnostics(url: url, issues: issues)
        }
        indexer.onProgress = { completed, total in
            Task { @MainActor in
                AppServices.projectScanStatus.update(root: root, completed: completed, total: total)
            }
        }
        indexes[key] = symbolIndex
        indexers[key] = indexer
        lock.unlock()

        Task.detached(priority: .utility) {
            await indexer.buildIndex(at: root)
        }
        return symbolIndex
    }

    // MARK: - Project-wide diagnostics

    private static func currentDiagnosticsConfig() -> PHPDiagnosticsConfig {
        let settings = AppServices.settings.preferences.phpDiagnostics
        var config = PHPDiagnosticsConfig()
        config.classLength = settings.classLength
        config.methodLength = settings.methodLength
        config.fileLength = settings.fileLength
        config.parameterCount = settings.parameterCount
        config.complexity = settings.complexity
        config.lineLength = settings.lineLength
        config.requireStrictTypes = settings.requireStrictTypes
        config.reportTodos = settings.reportTodos
        config.reportNaming = settings.reportNaming
        config.disabledRules = Set(settings.disabledRules)
        config.skipPatterns = settings.skipPatterns
        return config
    }

    /// Queues a file's diagnostics; flushes to the store in debounced batches (one rebuild per batch).
    private func enqueueDiagnostics(url: URL, issues: [PHPDiagnostic]) {
        lock.lock()
        pendingDiagnostics[url] = issues
        let shouldSchedule = !flushScheduled
        if shouldSchedule { flushScheduled = true }
        lock.unlock()
        guard shouldSchedule else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.flushDiagnostics()
        }
    }

    private func flushDiagnostics() {
        lock.lock()
        let batch = pendingDiagnostics
        pendingDiagnostics.removeAll()
        flushScheduled = false
        lock.unlock()
        guard !batch.isEmpty else { return }

        let mapped = batch.mapValues { issues in
            issues.map {
                EditorDiagnostic(range: $0.range, severity: $0.severity, message: $0.message, line: $0.line)
            }
        }
        Task { @MainActor in
            AppServices.diagnosticsStore.update(files: mapped)
        }
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

    /// Re-scans the whole workspace (re-parses + re-diagnoses every file). Used by the Problems panel.
    func rescan(root: URL) {
        let key = root.path(percentEncoded: false)
        lock.lock()
        let indexer = indexers[key]
        lock.unlock()
        guard let indexer else {
            _ = index(for: root)
            return
        }
        Task.detached(priority: .utility) {
            indexer.reprocessAll()
            await indexer.buildIndex(at: root)
        }
    }

    /// Removes a file's symbols and reference postings for a workspace root.
    func removeFile(_ file: URL, root: URL) {
        let key = root.path(percentEncoded: false)
        lock.lock()
        let indexer = indexers[key]
        let symbolIndex = indexes[key]
        lock.unlock()
        if let indexer {
            indexer.removeFile(file)
        } else {
            symbolIndex?.removeFile(file)
        }
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
                indexer.replace(file: file, with: info)
            }
        }
    }
}
