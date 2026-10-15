//
//  LSPLanguageProvider+Completion.swift
//  CodeEdit
//
//  Completion requests backed by the language server.
//

import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

extension LSPLanguageProvider {
    @MainActor
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        guard let server = server,
              let position = textView.textView.lspRangeFrom(nsRange: cursorPosition.range)?.start else {
            return nil
        }
        guard let response = try? await server.requestCompletion(for: documentURI, position: position) else {
            return nil
        }

        let items: [CompletionItem]
        switch response {
        case .optionA(let array):
            items = array
        case .optionB(let list):
            items = list.items
        }
        guard !items.isEmpty else {
            completionPosition = nil
            completionItems = []
            return nil
        }

        completionPosition = position
        completionItems = Array(items.prefix(200))
        return (cursorPosition, completionItems.map(Self.entry))
    }
}
