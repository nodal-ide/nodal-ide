//
//  CodeEditDocumentController.swift
//  CodeEdit
//
//  Created by Pavel Kasila on 17.03.22.
//

import Cocoa
import SwiftUI
import WelcomeWindow

final class CodeEditDocumentController: NSDocumentController {
    @Environment(\.openWindow)
    private var openWindow

    private var lspService: LSPService { AppServices.lspService }

    private let fileManager = FileManager.default

    @MainActor
    func createAndOpenNewDocument(onCompletion: @escaping () -> Void) {
        guard let newDocumentUrl = self.newDocumentUrl else { return }

        let settings = AppServices.settings.preferences.textEditing
        let fileContents: Data?
        if settings.enableFileHeader {
            let projectSettingsName = newDocumentUrl.findWorkspace()?
                .workspaceSettingsManager?
                .settings.project.projectName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let orgFallback = projectSettingsName.flatMap { $0.isEmpty ? nil : $0 } ?? "Nodal IDE"
            fileContents = FileHeaderGenerator.generateHeaderData(
                for: newDocumentUrl,
                organization: settings.fileHeaderOrganization.isEmpty
                    ? orgFallback
                    : settings.fileHeaderOrganization,
                author: settings.fileHeaderAuthor
            )
        } else {
            fileContents = nil
        }

        let createdFile = self.fileManager.createFile(
            atPath: newDocumentUrl.path,
            contents: fileContents,
            attributes: [FileAttributeKey.creationDate: Date()]
        )

        guard createdFile else {
            print("Failed to create new document")
            return
        }

        self.openDocument(withContentsOf: newDocumentUrl, display: true) { _, _, _ in
            onCompletion()
        }
    }

    override func newDocument(_ sender: Any?) {
        guard let newDocumentUrl = self.newDocumentUrl else { return }

        let settings = AppServices.settings.preferences.textEditing
        let fileContents: Data?
        if settings.enableFileHeader {
            let projectSettingsName = newDocumentUrl.findWorkspace()?
                .workspaceSettingsManager?
                .settings.project.projectName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let orgFallback = projectSettingsName.flatMap { $0.isEmpty ? nil : $0 } ?? "Nodal IDE"
            fileContents = FileHeaderGenerator.generateHeaderData(
                for: newDocumentUrl,
                organization: settings.fileHeaderOrganization.isEmpty
                    ? orgFallback
                    : settings.fileHeaderOrganization,
                author: settings.fileHeaderAuthor
            )
        } else {
            fileContents = nil
        }

        let createdFile = self.fileManager.createFile(
            atPath: newDocumentUrl.path,
            contents: fileContents,
            attributes: [FileAttributeKey.creationDate: Date()]
        )
        guard createdFile else {
            print("Failed to create new document")
            return
        }

        self.openDocument(withContentsOf: newDocumentUrl, display: true) { _, _, _ in }
    }

    private var newDocumentUrl: URL? {
        let panel = NSSavePanel()
        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    override func openDocument(_ sender: Any?) {
        self.openDocument(onCompletion: { document, documentWasAlreadyOpen in
            // TODO: handle errors

            guard let document else {
                print("Failed to unwrap document")
                return
            }

            print(document, documentWasAlreadyOpen)
        }, onCancel: {})
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        if let document = openFileInExistingWorkspace(url: url) {
            RecentsStore.documentOpened(at: url)
            completionHandler(document, true, nil)
            return
        }

        openDocumentWindow(
            withContentsOf: url,
            display: displayDocument,
            completionHandler: completionHandler
        )
    }

    /// Opens a file supplied from outside the app (Finder, Open With, `--open`) in its own window.
    ///
    /// Internal navigation (`openDocument`) keeps the existing workspace-reuse behavior so Open Quickly,
    /// references, problems, and assistant citations continue to open tabs in the workspace. External
    /// opens must not silently attach the file to an unrelated workspace.
    ///
    /// A file already open in a workspace is focused there instead of creating a second editor over the
    /// same `NSDocument`. A file already open in a standalone window is brought forward.
    func openDocumentInStandaloneWindow(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        guard !url.isFolder else {
            openDocument(
                withContentsOf: url,
                display: displayDocument,
                completionHandler: completionHandler
            )
            return
        }

        if let existing = document(for: url) as? CodeFileDocument {
            RecentsStore.documentOpened(at: url)
            if existing.windowControllers.isEmpty {
                // The document is hosted by a workspace tab rather than its own NSWindowController.
                if !focusExistingWorkspaceTab(for: url) {
                    existing.makeWindowControllers()
                    existing.showWindows()
                }
            } else {
                existing.showWindows()
            }
            completionHandler(existing, true, nil)
            return
        }

        openDocumentWindow(
            withContentsOf: url,
            display: displayDocument,
            completionHandler: completionHandler
        )
    }

    /// Creates a document/window through AppKit without the workspace-reuse check.
    private func openDocumentWindow(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        super.openDocument(withContentsOf: url, display: displayDocument) { document, documentWasAlreadyOpen, error in
            // `NSDocumentController` always invokes this completion handler on the main thread, so
            // assuming main-actor isolation here is sound and avoids an extra async hop that could
            // reorder document-open callbacks.
            MainActor.assumeIsolated {
                if let document {
                    self.addDocument(document)
                } else {
                    let errorMessage = error?.localizedDescription ?? "unknown error"
                    print("Unable to open document '\(url)': \(errorMessage)")
                }

                RecentsStore.documentOpened(at: url)
                completionHandler(document, documentWasAlreadyOpen, error)
            }
        }
    }

    /// Attempt to open the file URL in an open workspace, finding the nearest workspace to open it in if possible.
    /// - Parameter url: The file URL to open.
    /// - Returns: The opened document, or `nil` if no workspace could host it.
    @discardableResult
    private func openFileInExistingWorkspace(url: URL) -> CodeFileDocument? {
        guard !url.isFolder else { return nil }
        let workspaces = documents.compactMap({ $0 as? WorkspaceDocument })

        // Check open workspaces for the file being opened. Sorted by shared components with the url so we
        // open the nearest workspace possible.
        for workspace in workspaces.sorted(by: {
            ($0.fileURL?.sharedComponents(url) ?? 0) > ($1.fileURL?.sharedComponents(url) ?? 0)
        }) {
            // createIfNotFound will still return `nil` if the files don't share a common ancestor.
            if let newFile = workspace.workspaceFileManager?.getFile(url.absolutePath, createIfNotFound: true) {
                workspace.editorManager?.openTab(item: newFile)
                workspace.showWindows()
                if let windowController = workspace.windowControllers.first as? CodeEditWindowController {
                    windowController.revealInProjectNavigator(newFile)
                } else {
                    workspace.listenerModel.highlightedFileItem = newFile
                }
                return newFile.fileDocument
            }
        }
        return nil
    }

    /// Selects text from `url` in an existing workspace tab, without creating a second document.
    private func focusExistingWorkspaceTab(for url: URL) -> Bool {
        let workspaces = documents.compactMap({ $0 as? WorkspaceDocument })
            .sorted(by: {
                ($0.fileURL?.sharedComponents(url) ?? 0) > ($1.fileURL?.sharedComponents(url) ?? 0)
            })

        for workspace in workspaces {
            guard let file = workspace.workspaceFileManager?.getFile(url.absolutePath),
                  file.fileDocument != nil
            else { continue }
            workspace.editorManager?.openTab(item: file)
            workspace.showWindows()
            if let windowController = workspace.windowControllers.first as? CodeEditWindowController {
                windowController.revealInProjectNavigator(file)
            } else {
                workspace.listenerModel.highlightedFileItem = file
            }
            return true
        }
        return false
    }

    override func removeDocument(_ document: NSDocument) {
        super.removeDocument(document)

        if let workspace = document as? WorkspaceDocument, let path = workspace.fileURL?.absoluteURL.path() {
            lspService.closeWorkspace(path)
        }

        if CodeEditDocumentController.shared.documents.isEmpty {
            switch AppServices.settings[\.general].reopenWindowAfterClose {
            case .showWelcomeWindow:
                // Opens the welcome window
                openWindow(sceneID: .welcome)
            case .quit:
                // Quits CodeEdit
                NSApplication.shared.terminate(nil)
            case .doNothing: break
            }
        }
    }
}

extension NSDocumentController {
    final func openDocument(onCompletion: @escaping (NSDocument?, Bool) -> Void, onCancel: @escaping () -> Void) {
        let dialog = NSOpenPanel()

        dialog.title = "Open Workspace or File"
        dialog.showsResizeIndicator = true
        dialog.showsHiddenFiles = false
        dialog.canChooseFiles = true
        dialog.canChooseDirectories = true

        dialog.begin { result in
            if result ==  NSApplication.ModalResponse.OK, let url = dialog.url {
                self.openDocument(withContentsOf: url, display: true) { document, documentWasAlreadyOpen, error in
                    if let error {
                        NSAlert(error: error).runModal()
                        return
                    }

                    guard let document else {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString(
                            "Failed to get document",
                            comment: "Failed to get document"
                        )
                        alert.runModal()
                        return
                    }
                    onCompletion(document, documentWasAlreadyOpen)
                    print("Document:", document)
                    print("Was already open?", documentWasAlreadyOpen)
                }
            } else if result == NSApplication.ModalResponse.cancel {
                onCancel()
            }
        }
    }
}
