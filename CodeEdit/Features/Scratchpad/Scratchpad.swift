//
//  Scratchpad.swift
//  CodeEdit
//
//  Helpers for the untitled scratchpad file (⌘⇧N).
//

import AppKit

enum Scratchpad {
    /// True when the URL is an unsaved scratchpad (a temp file named `untitled`).
    static func isScratchpad(_ url: URL?) -> Bool {
        guard let url else { return false }
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        return url.deletingLastPathComponent().standardizedFileURL.path == temp
            && url.lastPathComponent.hasPrefix("untitled")
    }

    /// Prompts for a project-relative path and moves the scratchpad content there, creating
    /// intermediate directories. Accepts a plain name (`notes.md`) or a path (`src/notes.md`).
    @MainActor
    static func saveAs(file: CEWorkspaceFile, workspace: WorkspaceDocument, editor: Editor?) {
        guard let root = workspace.workspaceFileManager?.folderUrl else { return }

        let alert = NSAlert()
        alert.messageText = "Save As"
        alert.informativeText = "Enter a name or a path relative to the project (e.g. src/notes.md)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = file.name
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
            let content = (try? Data(contentsOf: file.url)) ?? Data()
            try content.write(to: target)
        } catch {
            NSAlert(error: error).runModal()
            return
        }

        // Remove the temp file and mark the document saved so it closes without prompting.
        try? FileManager.default.removeItem(at: file.url)
        file.fileDocument?.updateChangeCount(.changeCleared)

        editor?.closeTab(file: file)

        if let newFile = workspace.workspaceFileManager?.getFile(target.path, createIfNotFound: true) {
            workspace.editorManager?.activeEditor.openTab(file: newFile, asTemporary: false)
            workspace.listenerModel.highlightedFileItem = newFile
        }
    }
}