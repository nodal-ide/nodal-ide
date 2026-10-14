//
//  TextView+LSPRange.swift
//  CodeEdit
//
//  Created by Khan Winter on 9/21/24.
//

import AppKit
import CodeEditTextView
import LanguageServerProtocol

extension TextView {
    func lspRangeFrom(nsRange: NSRange) -> LSPRange? {
        guard let startLine = layoutManager.textLineForOffset(nsRange.location),
              let endLine = layoutManager.textLineForOffset(nsRange.max) else {
            return nil
        }
        return LSPRange(
            start: Position(line: startLine.index, character: nsRange.location - startLine.range.location),
            end: Position(line: endLine.index, character: nsRange.max - endLine.range.location)
        )
    }

    /// Converts an LSP range (0-indexed line/character) into a UTF-16 `NSRange` in this document.
    func nsRange(fromLSP range: LSPRange) -> NSRange? {
        guard let start = offset(forLSPPosition: range.start),
              let end = offset(forLSPPosition: range.end) else {
            return nil
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Converts an LSP position (0-indexed line/character) into a UTF-16 offset in this document.
    func offset(forLSPPosition position: Position) -> Int? {
        guard let line = layoutManager.textLineForIndex(position.line) else { return nil }
        return line.range.location + position.character
    }
}
