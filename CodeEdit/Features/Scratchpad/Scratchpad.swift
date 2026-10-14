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
        guard let fileManager = workspace.workspaceFileManager else { return }
        let root = fileManager.folderUrl

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

        let components = input.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard let fileName = components.last, fileName.isValidFilename else { return }
        let folderComponents = components.dropLast()

        let content = (try? Data(contentsOf: file.url)) ?? Data()

        // Navigate/create the destination folder using the file manager so the tree is indexed
        // consistently (and observers notified), instead of synthesizing detached items.
        guard var parent = fileManager.getFile(root.path, createIfNotFound: true) else { return }
        for folder in folderComponents {
            let candidateURL = parent.url.appending(path: folder)
            if let existing = fileManager.getFile(candidateURL.path), existing.isFolder {
                parent = existing
            } else if let created = try? fileManager.addFolder(folderName: folder, toFile: parent) {
                parent = created
            } else {
                return
            }
        }

        // Create (or overwrite) the file through the file manager so it's indexed and git-refreshed.
        let targetURL = parent.url.appending(path: fileName)
        let newFile: CEWorkspaceFile?
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? content.write(to: targetURL)
            try? fileManager.rebuildFiles(fromItem: parent)
            fileManager.notifyObservers(updatedItems: [parent])
            newFile = fileManager.getFile(targetURL.path)
        } else {
            newFile = try? fileManager.addFile(fileName: fileName, toFile: parent, contents: content)
        }

        // Open the saved file *before* closing the scratch tab, so the editor always has a tab and the
        // saved file stays open.
        if let newFile {
            workspace.editorManager?.activeEditor.openTab(file: newFile, asTemporary: false)
            workspace.listenerModel.highlightedFileItem = newFile
        }

        // Remove the temp file and close the scratch tab without prompting.
        file.fileDocument?.updateChangeCount(.changeCleared)
        try? FileManager.default.removeItem(at: file.url)
        editor?.closeTab(file: file)
    }
}