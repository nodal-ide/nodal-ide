//
//  WorkspaceDocument+Reveal.swift
//  CodeEdit
//
//  Reveals a source location: selects the file's tab (or opens it) and scrolls to the line.
//

import Foundation
import CodeEditSourceEditor

extension WorkspaceDocument {
    /// Reveals `line`/`column` in `url`, opening the file if needed and scrolling it into view.
    func revealSourceLocation(url: URL, line: Int, column: Int = 1) {
        if editorManager?.reveal(url: url, line: line, column: column) == true { return }
        CodeEditDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { [weak self] document, _, _ in
            (document as? CodeFileDocument)?.openOptions = .init(
                cursorPositions: [CursorPosition(line: max(1, line), column: max(1, column))]
            )
            self?.revealWhenReady(url: url, line: line, column: column, attempts: 8)
        }
    }

    /// Retries revealing until the file's editor has appeared.
    private func revealWhenReady(url: URL, line: Int, column: Int, attempts: Int) {
        if editorManager?.reveal(url: url, line: line, column: column) == true { return }
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.revealWhenReady(url: url, line: line, column: column, attempts: attempts - 1)
        }
    }
}
