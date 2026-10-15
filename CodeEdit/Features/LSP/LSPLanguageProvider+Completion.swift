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
        guard let server = server else {
            Self.logger.warning("completion: server nil (lang=\(self.languageID), path=\(self.workspacePath))")
            return nil
        }
        guard let position = textView.textView.lspRangeFrom(nsRange: cursorPosition.range)?.start else {
            Self.logger.warning("completion: position nil (range=\(cursorPosition.range))")
            return nil
        }
        let completionResponse: CompletionResponse
        do {
            completionResponse = try await server.requestCompletion(for: documentURI, position: position)
        } catch {
            Self.logger.warning("completion request failed: \(error.localizedDescription)")
            return nil
        }
        guard let response = completionResponse else {
            Self.logger.warning("completion: no response")
            return nil
        }

        let items: [CompletionItem]
        switch response {
        case .optionA(let array):
            items = array
        case .optionB(let list):
            items = list.items
        }
        Self.logger.warning("completion: \(items.count) item(s) at \(position.line):\(position.character)")
        guard !items.isEmpty else {
            completionPosition = nil
            completionItems = []
            return nil
        }

        completionPosition = position
        completionItems = Array(items.prefix(500))
        return (cursorPosition, completionItems.map(Self.entry))
    }
}
