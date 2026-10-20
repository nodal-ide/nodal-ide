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
        guard let fileManager = workspace.workspaceFileManager,
              let destination = promptForDestination(defaultName: file.name),
              let parent = resolveParent(
                  in: fileManager,
                  root: fileManager.folderUrl,
                  folders: destination.folders
              ) else { return }

        let content = content(of: file)
        let targetURL = parent.url.appending(path: destination.fileName)
        let newFile: CEWorkspaceFile?
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? content.write(to: targetURL)
            try? fileManager.rebuildFiles(fromItem: parent)
            fileManager.notifyObservers(updatedItems: [parent])
            newFile = fileManager.getFile(targetURL.path)
        } else {
            newFile = try? fileManager.addFile(
                fileName: destination.fileName,
                toFile: parent,
                contents: content
            )
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

    @MainActor
    private static func promptForDestination(
        defaultName: String
    ) -> (fileName: String, folders: [String])? {
        let alert = NSAlert()
        alert.messageText = "Save As"
        alert.informativeText = "Enter a name or a path relative to the project (e.g. src/notes.md)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        let components = input.split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." }
        guard let fileName = components.last, fileName.isValidFilename else { return nil }
        return (fileName, Array(components.dropLast()))
    }

    private static func content(of file: CEWorkspaceFile) -> Data {
        guard let doc = file.fileDocument else {
            return (try? Data(contentsOf: file.url)) ?? Data()
        }
        let encoding = doc.sourceEncoding ?? FileEncoding.utf8
        if let text = doc.content?.string {
            return (text as NSString).data(using: encoding.nsValue) ?? Data(text.utf8)
        }
        if let docData = try? doc.data(ofType: doc.fileType ?? "public.plain-text") {
            return docData
        }
        return (try? Data(contentsOf: file.url)) ?? Data()
    }

    @MainActor
    private static func resolveParent(
        in fileManager: CEWorkspaceFileManager,
        root: URL,
        folders: [String]
    ) -> CEWorkspaceFile? {
        guard var parent = fileManager.getFile(root.path, createIfNotFound: true) else { return nil }
        for folder in folders {
            let candidateURL = parent.url.appending(path: folder)
            if let existing = fileManager.getFile(candidateURL.path), existing.isFolder {
                parent = existing
            } else if let created = try? fileManager.addFolder(folderName: folder, toFile: parent) {
                parent = created
            } else {
                return nil
            }
        }
        return parent
    }
}
