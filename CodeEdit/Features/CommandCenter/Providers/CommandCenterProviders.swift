//
//  CommandCenterProviders.swift
//  CodeEdit
//
//  Registers the built-in Command Center providers for a workspace.
//

import Foundation

enum CommandCenterProviders {
    /// Registers (or replaces) the built-in providers for the given workspace.
    @MainActor
    static func register(for workspace: WorkspaceDocument) {
        let registry = CommandCenterRegistry.shared

        registry.register(CommandsProvider())
        registry.register(KnowledgeProvider())

        if let root = workspace.fileURL {
            registry.register(FilesProvider(workspaceURL: root))
        }
        registry.register(SymbolsProvider(workspace: workspace))
        if let manager = workspace.sourceControlManager {
            registry.register(GitProvider(manager: manager))
        }
        registry.register(RunProvider(workspace: workspace))
    }
}
