//
//  CodeEditWindowControllerExtensions.swift
//  CodeEdit
//
//  Created by Austin Condiff on 10/14/23.
//

import SwiftUI
import Combine

extension CodeEditWindowController {
    /// These are example items that added as commands to command palette
    func registerCommands() {
        AppServices.commandManager.addCommand(
            name: "Quick Open",
            title: "Quick Open",
            id: "quick_open",
            command: { [weak self] in self?.openQuickly(nil) }
        )

        AppServices.commandManager.addCommand(
            name: "Toggle Navigator",
            title: "Toggle Navigator",
            id: "toggle_left_sidebar",
            command: { [weak self] in self?.toggleFirstPanel() }
        )

        AppServices.commandManager.addCommand(
            name: "Toggle Inspector",
            title: "Toggle Inspector",
            id: "toggle_right_sidebar",
            command: { [weak self] in self?.toggleLastPanel() }
        )

        AppServices.commandManager.addCommand(
            name: "Toggle Assistant",
            title: "Toggle Assistant",
            id: "toggle_assistant",
            command: { [weak self] in self?.toggleAssistant() }
        )
    }

    // Listen to changes in all tabs/files
    internal func listenToDocumentEdited(workspace: WorkspaceDocument) {
        workspace.editorManager?.$activeEditor
            .flatMap({ editor in
                editor.$tabs
            })
            .compactMap({ tab in
                Publishers.MergeMany(tab.elements.compactMap({ $0.file.fileDocumentPublisher }))
            })
            .switchToLatest()
            .compactMap({ fileDocument in
                fileDocument?.isDocumentEditedPublisher
            })
            .flatMap({ $0 })
            .sink { isDocumentEdited in
                if isDocumentEdited {
                    self.setDocumentEdited(true)
                    return
                }

                self.updateDocumentEdited(workspace: workspace)
            }
            .store(in: &cancellables)

        // Listen to change of tabs, if closed tab without saving content,
        // we also need to recalculate isDocumentEdited
        workspace.editorManager?.$activeEditor
            .flatMap({ editor in
                editor.$tabs
            })
            .sink { _ in
                self.updateDocumentEdited(workspace: workspace)
            }
            .store(in: &cancellables)
    }

    // Recalculate documentEdited by checking if any tab/file is edited
    private func updateDocumentEdited(workspace: WorkspaceDocument) {
        let hasEditedDocuments = !(workspace
            .editorManager?
            .editorLayout
            .gatherOpenFiles()
            .filter({ $0.fileDocument?.isDocumentEdited == true })
            .isEmpty ?? true)
        self.setDocumentEdited(hasEditedDocuments)
    }

    @IBAction func openWorkspaceSettings(_ sender: Any) {
        guard let workspace = workspace,
              let workspaceSettingsManager = workspace.workspaceSettingsManager,
              let taskManager = workspace.taskManager
        else { return }

        if let workspaceSettingsWindow, workspaceSettingsWindow.isVisible {
            workspaceSettingsWindow.makeKeyAndOrderFront(self)
        } else {
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            self.workspaceSettingsWindow = settingsWindow
            let contentView = CEWorkspaceSettingsView(
                dismiss: { [weak settingsWindow] in
                    settingsWindow?.close()
                }
            )
            .environmentObject(workspaceSettingsManager)
            .environmentObject(workspace)
            .environmentObject(taskManager)

            settingsWindow.contentView = NSHostingView(rootView: contentView)
            settingsWindow.title = "Project Settings"
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.toolbarStyle = .unified
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.setAccessibilityTitle("Project Settings")
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(self)
        }
    }
}

extension NSToolbarItem.Identifier {
    static let toggleFirstSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("ToggleFirstSidebarItem")
    static let toggleLastSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("ToggleLastSidebarItem")
    static let stopTaskSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("StopTaskSidebarItem")
    static let startTaskSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("StartTaskSidebarItem")
    static let itemListTrackingSeparator = NSToolbarItem.Identifier("ItemListTrackingSeparator")
    static let branchPicker: NSToolbarItem.Identifier = NSToolbarItem.Identifier("BranchPicker")
    static let activityViewer: NSToolbarItem.Identifier = NSToolbarItem.Identifier("ActivityViewer")
    static let notificationItem = NSToolbarItem.Identifier("notificationItem")

    static let taskSidebarItem: NSToolbarItem.Identifier = NSToolbarItem.Identifier("TaskSidebarItem")
}
