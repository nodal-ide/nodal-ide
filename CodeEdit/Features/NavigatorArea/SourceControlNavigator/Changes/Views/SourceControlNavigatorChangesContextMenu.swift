import AppKit
import SwiftUI

/// Context menu shared by the single-repository and multi-repository changes lists.
struct SourceControlNavigatorChangesContextMenu: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    let files: [GitChangedFile]
    let sourceControlManager: SourceControlManager

    var body: some View {
        if files.count == 1, let file = files.first {
            Group {
                Button("View in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file.fileURL.absoluteURL])
                }
                Button("Reveal in Project Navigator") {}
                    .disabled(true)
                Divider()
            }
            Group {
                Button("Open in New Tab") {
                    open(file)
                }
                Button("Open in New Window") {
                    openInNewWindow(file)
                }
                Divider()
                Button("Show Diff") {
                    AppServices.diffViewerPresenter.show(file: file, manager: sourceControlManager)
                }
                Button("Show Blame") {
                    AppServices.blameViewerPresenter.show(url: file.fileURL, manager: sourceControlManager)
                }
                Button("Resolve Conflicts") {
                    AppServices.conflictResolverPresenter.show(url: file.fileURL, manager: sourceControlManager)
                }
            }
            if file.anyStatus() != .none {
                Group {
                    Divider()
                    Button("Discard Changes in \(file.fileURL.lastPathComponent)...") {
                        sourceControlManager.discardChanges(for: file.fileURL)
                    }
                    Divider()
                }
            }
        }
    }

    private func open(_ file: GitChangedFile) {
        guard let ceFile = workspace.workspaceFileManager?.getFile(file.ceFileKey, createIfNotFound: true) else {
            return
        }
        DispatchQueue.main.async {
            workspace.editorManager?.openTab(item: ceFile, asTemporary: true)
        }
    }

    private func openInNewWindow(_ file: GitChangedFile) {
        (CodeEditDocumentController.shared as? CodeEditDocumentController)?
            .openDocumentInStandaloneWindow(withContentsOf: file.fileURL.absoluteURL, display: true) { _, _, _ in }
    }
}
