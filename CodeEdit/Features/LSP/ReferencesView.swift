//
//  ReferencesView.swift
//  CodeEdit
//
//  Find References results, shown in a search panel. Selecting a row opens the file at the reference.
//

import Combine
import SwiftUI
import CodeEditSourceEditor

struct ReferencesView: View {
    @ObservedObject private var state: ReferencesViewModel
    private let onClose: () -> Void

    init(state: ReferencesViewModel, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
    }

    var body: some View {
        SearchPanelView<AnyView, AnyView, PaletteItem>(
            title: "Filter references",
            image: Image(systemName: "arrow.turn.up.right"),
            options: $state.results,
            text: $state.query,
            alwaysShowOptions: true,
            optionRowHeight: 34
        ) { item in
            AnyView(CommandPaletteRowView(item: item))
        } onRowClick: { item in
            open(item)
        } onClose: {
            onClose()
        }
        .onReceive(state.$query.debounce(for: 0.1, scheduler: DispatchQueue.main)) { _ in
            state.filter()
        }
    }

    private func open(_ item: PaletteItem) {
        guard let url = item.fileURL else {
            onClose()
            return
        }
        CodeEditDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
            if let range = item.range {
                (document as? CodeFileDocument)?.openOptions = .init(
                    cursorPositions: [CursorPosition(range: range)]
                )
            }
        }
        onClose()
    }
}
