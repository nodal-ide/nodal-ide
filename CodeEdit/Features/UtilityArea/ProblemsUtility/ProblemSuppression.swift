//
//  ProblemSuppression.swift
//  CodeEdit
//
//  Inserts `// @codeedit-ignore-next-line <rule>` comments for a diagnostic into its source file.
//  Extracted from `ProblemsView` so the view stays free of document/IO logic.
//

import AppKit
import Foundation

enum ProblemSuppression {
    static func ignoreRule(_ problem: EditorProblem) {
        guard let ruleID = problem.ruleID else { return }
        CodeEditDocumentController.shared.openDocument(
            withContentsOf: problem.fileURL,
            display: true
        ) { document, _, _ in
            guard let document = document as? CodeFileDocument, let content = document.content else { return }
            let text = content.string as NSString
            let offset = offset(forLine: (problem.line ?? 1) - 1, column: 0, in: text)
            let indent = leadingWhitespace(in: text, at: offset)
            content.replaceCharacters(
                in: NSRange(location: offset, length: 0),
                with: "\(indent)// @codeedit-ignore-next-line \(ruleID)\n"
            )
            document.updateChangeCount(.changeDone)
        }
    }

    /// UTF-16 offset of a 0-indexed line/column in `text`.
    static func offset(forLine line: Int, column: Int, in text: NSString) -> Int {
        var currentLine = 0
        var index = 0
        while index < text.length, currentLine < line {
            if text.character(at: index) == 0x0A {
                currentLine += 1
            }
            index += 1
        }
        return min(index + max(0, column), text.length)
    }

    /// The leading spaces/tabs at `offset`, used to match the line's indentation.
    static func leadingWhitespace(in text: NSString, at offset: Int) -> String {
        var index = offset
        while index < text.length {
            let char = text.character(at: index)
            if char == 0x20 || char == 0x09 {
                index += 1
            } else {
                break
            }
        }
        return text.substring(with: NSRange(location: offset, length: index - offset))
    }
}
