//
//  FilesProvider.swift
//  CodeEdit
//
//  Command Center provider: workspace files.
//

import Foundation
import CollectionConcurrencyKit

@MainActor
final class FilesProvider: CommandCenterProvider {
    let id = "files"
    let category: CommandCenterCategory = .files
    let priority = 60

    private let workspaceURL: URL

    init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    func search(_ query: String) async -> [CommandCenterItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let root = workspaceURL
        return await Task.detached(priority: .userInitiated) { () -> [CommandCenterItem] in
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
            )
            let urls = (enumerator?.allObjects as? [URL]) ?? []
            guard !Task.isCancelled else { return [] }

            let files = urls.filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }

            let matches = await files.fuzzySearch(query: trimmed).concurrentMap { match in
                CommandCenterItem(
                    id: "file:\(match.item.path)",
                    title: match.item.lastPathComponent,
                    subtitle: Self.relativePath(match.item, root: root),
                    systemImage: "doc",
                    category: .files,
                    kind: .file(match.item, nil),
                    matchedCharacters: match.result.matchedParts
                )
            }
            return matches
        }.value
    }

    nonisolated private static func relativePath(_ url: URL, root: URL) -> String {
        let path = url.path(percentEncoded: false)
        let base = root.path(percentEncoded: false)
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
    }
}
