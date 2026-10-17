//
//  StartTaskToolbarItem.swift
//  CodeEdit
//
//  Created by Khan Winter on 8/28/25.
//

import AppKit

@available(macOS 26, *)
final class StartTaskToolbarItem: NSToolbarItem {
    private weak var workspace: WorkspaceDocument?

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
        super.init(itemIdentifier: NSToolbarItem.Identifier("StartTaskToolbarItem"))

        image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        image = image?.withSymbolConfiguration(config) ?? image

        paletteLabel = "Start Task"
        toolTip = "Run the selected task"
        target = self
        action = #selector(startTask)
        isBordered = true
    }

    @objc
    func startTask() {
        guard let taskManager = workspace?.taskManager else { return }

        taskManager.executeActiveTask()
        workspace?.utilityAreaModel?.open(tab: .console)
        taskManager.taskShowingOutput = taskManager.selectedTaskID
    }
}
