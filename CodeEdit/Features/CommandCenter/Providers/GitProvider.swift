//
//  GitProvider.swift
//  CodeEdit
//
//  Command Center provider: branches and changed files.
//

import Foundation

@MainActor
final class GitProvider: CommandCenterProvider {
    let id = "git"
    let category: CommandCenterCategory = .git
    let priority = 30

    private weak var manager: SourceControlManager?

    init(manager: SourceControlManager) {
        self.manager = manager
    }

    func search(_ query: String) async -> [CommandCenterItem] {
        guard let manager else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        var items: [CommandCenterItem] = []

        for branch in manager.branches where matches(branch.name, trimmed) {
            items.append(
                CommandCenterItem(
                    id: "git:branch:\(branch.longName)",
                    title: branch.name,
                    subtitle: "Branch",
                    systemImage: "arrow.triangle.branch",
                    category: .git,
                    kind: .route("git:checkout:\(branch.name)")
                )
            )
        }

        for file in manager.changedFiles where matches(file.fileURL.lastPathComponent, trimmed) {
            items.append(
                CommandCenterItem(
                    id: "git:changed:\(file.fileURL.path)",
                    title: file.fileURL.lastPathComponent,
                    subtitle: "\(file.anyStatus().description) — changed",
                    systemImage: "doc.badge.ellipsis",
                    category: .git,
                    kind: .file(file.fileURL, nil)
                )
            )
        }

        return items
    }

    private func matches(_ value: String, _ query: String) -> Bool {
        query.isEmpty || value.lowercased().contains(query)
    }
}
