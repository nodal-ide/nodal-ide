//
//  LSPLanguageProvider+Snippets.swift
//  CodeEdit
//
//  Snippet-format completion support (insertTextFormat == .snippet).
//

import AppKit
import CodeEditSourceEditor
import LanguageServerProtocol

extension LSPLanguageProvider {
    /// Expands a snippet-format completion: replaces the edit range with the snippet's literal text and
    /// starts a tab-stop session, then applies any additional edits (e.g. auto-imports).
    func applySnippetCompletion(
        _ item: CompletionItem,
        startPosition: Position,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        let mainText: String
        let mainRange: NSRange
        if let edit = item.textEdit {
            switch edit {
            case .optionA(let textEdit):
                guard let range = textView.textView.nsRange(fromLSP: textEdit.range) else { return }
                mainText = textEdit.newText
                mainRange = range
            case .optionB(let insertReplace):
                guard let range = textView.textView.nsRange(fromLSP: insertReplace.replace) else { return }
                mainText = insertReplace.newText
                mainRange = range
            }
        } else {
            mainText = item.insertText ?? item.label
            let start = textView.textView.offset(forLSPPosition: startPosition) ?? 0
            let cursor = cursorPosition?.range.location ?? start
            mainRange = NSRange(location: start, length: max(0, cursor - start))
        }

        textView.insertSnippet(mainText, replacing: mainRange)

        // Additional edits (e.g. imports) — applied after the snippet; the session tracks the shifts.
        if let additional = item.additionalTextEdits, !additional.isEmpty {
            let resolved = additional.compactMap { edit -> (NSRange, String)? in
                guard let range = textView.textView.nsRange(fromLSP: edit.range) else { return nil }
                return (range, edit.newText)
            }.sorted { $0.0.location > $1.0.location }
            for (range, text) in resolved {
                textView.textView.replaceCharacters(in: range, with: text)
            }
        }
    }
}
