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
        case let .file(url, range):
            open(url, range: range)
        case let .symbol(url, range):
            open(url, range: range)
        case let .position(url, line, character):
            open(url, range: nil, position: (line, character))
        case .command(let id):
            AppServices.commandManager.executeCommand(id)
        case .route(let route):
            handle(route, workspace: workspace)
        }
    }

    private static func open(_ url: URL, range: NSRange?, position: (line: Int, character: Int)? = nil) {
        CodeEditDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
            guard let document = document as? CodeFileDocument else { return }
            var cursor: NSRange?
            if let range {
                cursor = range
            } else if let position, let content = document.content?.string {
                cursor = NSRange(
                    location: offset(forLine: position.line, column: position.character, in: content as NSString),
                    length: 0
                )
            }
            if let cursor {
                document.openOptions = .init(cursorPositions: [CursorPosition(range: cursor)])
            }
        }
    }

    private static func offset(forLine line: Int, column: Int, in text: NSString) -> Int {
        var currentLine = 0
        var index = 0
        while index < text.length, currentLine < line {
            if text.character(at: index) == 0x0A {
                currentLine += 1
            }
            index += 1
        }
        return min(index + column, text.length)
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
            let tasks = workspace.workspaceSettingsManager?.settings.tasks ?? []
            guard let task = tasks.first(where: { $0.id.uuidString == id }),
                  let manager = workspace.taskManager else {
                return
            }
            Task { await manager.runTask(task: task) }
        } else if route.hasPrefix("knowledge:") {
            let destination = route.dropFirst("knowledge:".count)
            guard let separator = destination.firstIndex(of: ":") else { return }
            let sourceID = String(destination[..<separator])
            let path = String(destination[destination.index(after: separator)...])
            AppServices.knowledgeRouter.requestOpen(sourceID: sourceID, path: path)
            NSApp.sendAction(#selector(AppDelegate.openKnowledge(_:)), to: nil, from: nil)
        }
    }
}
