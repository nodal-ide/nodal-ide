//
//  EditorTabBarContextMenu.swift
//  CodeEdit
//
//  Created by Khan Winter on 6/4/22.
//

import SwiftUI
import Foundation

extension View {
    func tabBarContextMenu(item: CEWorkspaceFile, isTemporary: Bool) -> some View {
        modifier(EditorTabBarContextMenu(item: item, isTemporary: isTemporary))
    }
}

struct EditorTabBarContextMenu: ViewModifier {
    init(
        item: CEWorkspaceFile,
        isTemporary: Bool
    ) {
        self.item = item
        self.isTemporary = isTemporary
    }

    @EnvironmentObject var workspace: WorkspaceDocument

    @EnvironmentObject var tabs: Editor

    @Environment(\.splitEditor)
    var splitEditor

    private var item: CEWorkspaceFile
    private var isTemporary: Bool

    // swiftlint:disable:next function_body_length
    func body(content: Content) -> some View {
        content.contextMenu(menuItems: {
            Group {
                Button("Close Tab") {
                    withAnimation {
                        tabs.closeTab(file: item)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command])

                Button("Close Other Tabs") {
                    withAnimation {
                        tabs.tabs.map({ $0.file }).forEach { file in
                            if file != item {
                                tabs.closeTab(file: file)
                            }
                        }
                    }
                }

                Button("Close Tabs to the Right") {
                    withAnimation {
                        if let index = tabs.tabs.firstIndex(where: { $0.file == item }), index + 1 < tabs.tabs.count {
                            tabs.tabs[(index + 1)...].forEach {
                                tabs.closeTab(file: $0.file)
                            }
                        }
                    }
                }
                // Disable this option when current tab is the last one.
                .disabled(tabs.tabs.last?.file == item)

                Button("Close All") {
                    withAnimation {
                        tabs.tabs.forEach {
                            tabs.closeTab(file: $0.file)
                        }
                    }
                }

                if isTemporary {
                    Button("Keep Open") {
                        tabs.temporaryTab = nil
                    }
                }

                if Self.isScratchpad(item) {
                    Button("Save As…") {
                        saveScratchpadAs()
                    }
                }
            }

            Divider()

            Group {
                Button("Copy Path") {
                    copyPath(item: item)
                }

                Button("Copy Relative Path") {
                    copyRelativePath(item: item)
                }
            }

            Divider()

            Group {
                Button("Show in Finder") {
                    item.showInFinder()
                }

                Button("Reveal in Project Navigator") {
                    workspace.listenerModel.highlightedFileItem = item
                }

                Button("Open in New Window") {

                }
                .disabled(true)
            }

            Divider()

            Button("Split Up") {
                moveToNewSplit(.top)
            }
            Button("Split Down") {
                moveToNewSplit(.bottom)
            }
            Button("Split Left") {
                moveToNewSplit(.leading)
            }
            Button("Split Right") {
                moveToNewSplit(.trailing)
            }
        })
    }

    // MARK: - Scratchpad

    /// True when the file is an unsaved scratchpad (a temp file named `untitled`).
    static func isScratchpad(_ item: CEWorkspaceFile) -> Bool {
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        return item.url.deletingLastPathComponent().standardizedFileURL.path == temp
            && item.name.hasPrefix("untitled")
    }

    /// Prompts for a project-relative path and moves the scratchpad content there,
    /// creating intermediate directories as needed.
    private func saveScratchpadAs() {
        guard let root = workspace.workspaceFileManager?.folderUrl else { return }

        let alert = NSAlert()
        alert.messageText = "Save As"
        alert.informativeText = "Enter a name or a path relative to the project (e.g. src/notes.md)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = item.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let target = root.appendingPathComponent(input).standardizedFileURL
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let content = (try? Data(contentsOf: item.url)) ?? Data()
            try content.write(to: target)
        } catch {
            NSAlert(error: error).runModal()
            return
        }

        // Remove the temp file and mark the document saved so it closes without prompting.
        try? FileManager.default.removeItem(at: item.url)
        item.fileDocument?.updateChangeCount(.changeCleared)

        tabs.closeTab(file: item)

        if let newFile = workspace.workspaceFileManager?.getFile(target.path, createIfNotFound: true) {
            workspace.editorManager?.activeEditor.openTab(file: newFile, asTemporary: false)
            workspace.listenerModel.highlightedFileItem = newFile
        }
    }

    // MARK: - Actions

    /// Copies the absolute path of the given `FileItem`
    /// - Parameter item: The `FileItem` to use.
    private func copyPath(item: CEWorkspaceFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.standardizedFileURL.path, forType: .string)
    }

    func moveToNewSplit(_ edge: Edge) {
        let newEditor = Editor(files: [item], workspace: workspace)
        splitEditor(edge, newEditor)
        tabs.closeTab(file: item)
        workspace.editorManager?.activeEditor = newEditor
    }

    /// Copies the relative path from the workspace folder to the given file item to the pasteboard.
    /// - Parameter item: The `FileItem` to use.
    private func copyRelativePath(item: CEWorkspaceFile) {
        guard let rootPath = workspace.workspaceFileManager?.folderUrl else {
            return
        }
        let destinationComponents = item.url.standardizedFileURL.pathComponents
        let baseComponents = rootPath.standardizedFileURL.pathComponents

        // Find common prefix length
        var prefixCount = 0
        while prefixCount < min(destinationComponents.count, baseComponents.count)
                && destinationComponents[prefixCount] == baseComponents[prefixCount] {
            prefixCount += 1
        }
        // Build the relative path
        let upPath = String(repeating: "../", count: baseComponents.count - prefixCount)
        let downPath = destinationComponents[prefixCount...].joined(separator: "/")

        // Copy it to the clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(upPath + downPath, forType: .string)
    }
}
