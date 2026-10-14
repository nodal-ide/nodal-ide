//
//  PaletteItem.swift
//  CodeEdit
//
//  A unified item for the ⌘K command center (file, symbol, or command).
//

import Foundation
import CodeEditLang

struct PaletteItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case file
        case symbol
        case command
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let fileURL: URL?
    let range: NSRange?
    let commandID: String?
    let matchedCharacters: [NSRange]
    let symbolKind: SymbolKind?
}