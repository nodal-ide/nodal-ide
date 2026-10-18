//
//  CommandsProvider.swift
//  CodeEdit
//
//  Command Center provider: app commands.
//

import Foundation

@MainActor
final class CommandsProvider: CommandCenterProvider {
    let id = "commands"
    let category: CommandCenterCategory = .commands
    let priority = 80

    func search(_ query: String) async -> [CommandCenterItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let all = AppServices.commandManager.commands
        let filtered = trimmed.isEmpty
            ? all
            : all.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }

        return filtered
            .sorted { $0.title < $1.title }
            .map { command in
                CommandCenterItem(
                    id: "cmd:\(command.id)",
                    title: command.title,
                    subtitle: "Command",
                    systemImage: "command",
                    category: .commands,
                    kind: .command(command.id)
                )
            }
    }
}
