//
//  ExtensionItem.swift
//  CodeEdit
//

import Foundation

/// A row in the Extensions window: either an ExtensionKit app extension or a declarative
/// language extension (pack).
enum ExtensionItem: Identifiable, Hashable {
    case app(ExtensionInfo)
    case language(InstalledLanguageExtension)

    var id: String {
        switch self {
        case .app(let info):
            return "app:" + info.id
        case .language(let ext):
            return "lang:" + ext.id
        }
    }

    var name: String {
        switch self {
        case .app(let info):
            return info.name
        case .language(let ext):
            return ext.name
        }
    }
}
