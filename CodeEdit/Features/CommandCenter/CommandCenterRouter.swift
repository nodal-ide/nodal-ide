//
//  CommandCenterRouter.swift
//  CodeEdit
//
//  Activates a Command Center item.
//

import AppKit
import CodeEditSourceEditor

@MainActor
enum CommandCenterRouter {
    static func activate(_ item: CommandCenterItem, workspace: WorkspaceDocument?) {
        switch item.kind {
        case .file(let url, let range):
            open(url, range: range)
        case .symbol(let url, let range):
            open(url, range: range)
        case .command(let id):
            CommandManager.shared.executeCommand(id)
        case .route(let route):
            handle(route, workspace: workspace)
        }
    }

    private static func open(_ url: URL, range: NSRange?) {
        CodeEditDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
            guard let range, let document = document as? CodeFileDocument else { return }
            document.openOptions = .init(cursorPositions: [CursorPosition(range: range)])
        }
    }

    private static func handle(_ route: String, workspace: WorkspaceDocument?) {
        guard let workspace else { return }

        if route.hasPrefix("git:checkout:") {
            let name = String(route.dropFirst("git:checkout:".count))
            guard let branch = workspace.sourceControlManager?.branches.first(where: { $0.name == name }) else {
                return
            }
            Task { try? await workspace.sourceControlManager?.checkoutBranch(branch: branch) }
        } else if route.hasPrefix("run:") {
            let id = String(route.dropFirst("run:".count))
            guard let task = workspace.workspaceSettingsManager?.settings.tasks.first(where: { $0.id.uuidString == id }),
                  let manager = workspace.taskManager else {
                return
            }
            Task { await manager.runTask(task: task) }
        }
        // `knowledge:` routes are handled by the Knowledge window (opened separately).
    }
}
