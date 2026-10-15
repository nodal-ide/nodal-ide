//
//  CommandCenterItem.swift
//  CodeEdit
//
//  A single result shown in the Command Center, produced by a provider.
//

import Foundation

struct CommandCenterItem: Identifiable, Hashable {
    /// What activating the item does. Kept free of closures so the item stays `Hashable`.
    enum Kind: Hashable {
        case file(URL, NSRange?)
        case command(String)
        case symbol(URL, NSRange)
        /// A file position (0-based line/character), e.g. from LSP workspace symbols.
        case position(URL, Int, Int)
        /// A provider-specific route string, resolved by the router.
        case route(String)
    }

    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let category: CommandCenterCategory
    let kind: Kind
    /// A right-aligned accessory (e.g. a keyboard shortcut).
    let accessory: String?
    /// Ranges in `title` to highlight (fuzzy match), if any.
    let matchedCharacters: [NSRange]

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        category: CommandCenterCategory,
        kind: Kind,
        accessory: String? = nil,
        matchedCharacters: [NSRange] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.category = category
        self.kind = kind
        self.accessory = accessory
        self.matchedCharacters = matchedCharacters
    }
}
