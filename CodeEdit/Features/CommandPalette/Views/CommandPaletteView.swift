//
//  CommandPaletteView.swift
//  CodeEdit
//
//  The ⌘K command center: files (default), symbols (`@`), commands (`>`).
//

import SwiftUI
import CodeEditSourceEditor

struct CommandPaletteView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @ObservedObject private var state: CommandPaletteViewModel

    private let onClose: () -> Void

    init(state: CommandPaletteViewModel, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
    }

    var body: some View {
        SearchPanelView<AnyView, AnyView, PaletteItem>(
            title: "Search files, symbols (@), commands (>)",
            image: Image(systemName: "magnifyingglass"),
            options: $state.results,
            text: $state.query,
            alwaysShowOptions: true,
            optionRowHeight: 36
        ) { item in
            AnyView(CommandPaletteRowView(item: item))
        } preview: { item in
            AnyView(CommandPalettePreviewView(item: item))
        } onRowClick: { item in
            perform(item)
            onClose()
        } onClose: {
            onClose()
        }
        .onReceive(state.$query.debounce(for: 0.15, scheduler: DispatchQueue.main)) { _ in
            state.fetchResults()
        }
    }

    private func perform(_ item: PaletteItem) {
        switch item.kind {
        case .file:
            guard let url = item.fileURL,
                  let file = workspace.workspaceFileManager?.getFile(
                      url.relativePath,
                      createIfNotFound: true
                  ) else {
                return
            }
            workspace.editorManager?.openTab(item: file)

        case .symbol:
            guard let url = item.fileURL else { return }
            CodeEditDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            ) { document, _, _ in
                guard let range = item.range else { return }
                (document as? CodeFileDocument)?.openOptions = .init(
                    cursorPositions: [CursorPosition(range: range)]
                )
            }

        case .command:
            if let id = item.commandID {
                CommandManager.shared.executeCommand(id)
            }
        }
    }
}