//
//  CommandPaletteViewModel.swift
//  CodeEdit
//
//  Backs the ⌘K command center. Default search is files; prefix `@` searches symbols
//  (workspace index) and `>` searches commands.
//

import Foundation
import Combine
import CollectionConcurrencyKit
import CodeEditLang

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [PaletteItem] = []

    let workspaceURL: URL
    private var runningTask: Task<Void, Never>?

    init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    func reset() {
        query = ""
        results = []
        runningTask?.cancel()
    }

    func fetchResults() {
        runningTask?.cancel()
        let raw = query.trimmingCharacters(in: .whitespaces)

        if raw.hasPrefix(">") {
            commands(query: String(raw.dropFirst()).trimmingCharacters(in: .whitespaces))
        } else if raw.hasPrefix("@") {
            symbols(query: String(raw.dropFirst()).trimmingCharacters(in: .whitespaces))
        } else {
            files(query: raw)
        }
    }

    // MARK: - Commands

    private func commands(query: String) {
        let all = CommandManager.shared.commands
        let filtered = query.isEmpty
            ? all
            : all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        results = filtered
            .sorted { $0.title < $1.title }
            .map { command in
                PaletteItem(
                    id: "cmd:\(command.id)",
                    kind: .command,
                    title: command.title,
                    subtitle: "Command",
                    fileURL: nil,
                    range: nil,
                    commandID: command.id,
                    matchedCharacters: [],
                    symbolKind: nil
                )
            }
    }

    // MARK: - Symbols

    private func symbols(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        let index = PHPWorkspaceIndex.shared.index(for: workspaceURL)
        results = index.symbols(prefix: query, limit: 100).map { symbol in
            PaletteItem(
                id: "sym:\(symbol.fullyQualifiedName):\(symbol.fileURL.path):\(symbol.nameRange.location)",
                kind: .symbol,
                title: symbol.name,
                subtitle: symbol.container ?? symbol.namespace ?? symbol.fullyQualifiedName,
                fileURL: symbol.fileURL,
                range: symbol.nameRange,
                commandID: nil,
                matchedCharacters: [],
                symbolKind: symbol.kind
            )
        }
    }

    // MARK: - Files

    private func files(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        let root = workspaceURL
        runningTask = Task.detached(priority: .userInitiated) {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
            )
            let filePaths = (enumerator?.allObjects as? [URL]) ?? []
            guard !Task.isCancelled else { return }

            let regularFiles = filePaths.filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }

            let fuzzy = await regularFiles.fuzzySearch(query: query).concurrentMap { match in
                PaletteItem(
                    id: "file:\(match.item.path)",
                    kind: .file,
                    title: match.item.lastPathComponent,
                    subtitle: nil,
                    fileURL: match.item,
                    range: nil,
                    commandID: nil,
                    matchedCharacters: match.result.matchedParts,
                    symbolKind: nil
                )
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.results = fuzzy
            }
        }
    }
}