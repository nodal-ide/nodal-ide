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
    var supportsCompletionRefresh: Bool { true }

    @MainActor
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        guard let result = await requestCompletion(
            textView: textView,
            cursorPosition: cursorPosition
        ) else {
            return nil
        }
        return (cursorPosition, result.items)
    }

    @MainActor
    func completionResultRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> CompletionResult? {
        await requestCompletion(textView: textView, cursorPosition: cursorPosition)
    }

    @MainActor
    func completionRefreshRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> CompletionResult? {
        await requestCompletion(textView: textView, cursorPosition: cursorPosition)
    }

    private static let maximumItems = 500

    @MainActor
    private func requestCompletion(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> CompletionResult? {
        // Coalesce rapid re-requests while typing: a newer request cancels this one before it hits the server.
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled else { return nil }

        guard let server = server,
              let position = textView.textView.lspRangeFrom(nsRange: cursorPosition.range)?.start else {
            return nil
        }
        guard let response = try? await server.requestCompletion(for: documentURI, position: position) else {
            return nil
        }

        let items: [CompletionItem]
        let isIncomplete: Bool
        switch response {
        case .optionA(let array):
            items = array
            isIncomplete = false
        case .optionB(let list):
            items = list.items
            isIncomplete = list.isIncomplete
        }
        guard !items.isEmpty else {
            completionPosition = nil
            completionItems = []
            return nil
        }

        completionPosition = position
        completionItems = Array(items.prefix(Self.maximumItems))
        return CompletionResult(
            items: completionItems.map(Self.entry),
            isIncomplete: isIncomplete
        )
    }
}
