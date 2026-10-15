//
//  RunProvider.swift
//  CodeEdit
//
//  Command Center provider: workspace tasks (run).
//

import Foundation

@MainActor
final class RunProvider: CommandCenterProvider {
    let id = "run"
    let category: CommandCenterCategory = .run
    let priority = 50

    private weak var workspace: WorkspaceDocument?

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    func search(_ query: String) async -> [CommandCenterItem] {
        guard let tasks = workspace?.workspaceSettingsManager?.settings.tasks else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()

        return tasks
            .filter { !$0.isInvalid && (trimmed.isEmpty || $0.name.lowercased().contains(trimmed)) }
            .map { task in
                CommandCenterItem(
                    id: "run:\(task.id)",
                    title: task.name,
                    subtitle: task.command.isEmpty ? "Task" : task.command,
                    systemImage: "play",
                    category: .run,
                    kind: .route("run:\(task.id)")
                )
            }
    }
}
