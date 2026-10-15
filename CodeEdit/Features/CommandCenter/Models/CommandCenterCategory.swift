//
//  CommandCenterCategory.swift
//  CodeEdit
//
//  Categories (tabs) for the Command Center.
//

import Foundation

enum CommandCenterCategory: String, CaseIterable, Identifiable {
    case all
    case files
    case symbols
    case commands
    case content
    case git
    case knowledge
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .files: return "Files"
        case .symbols: return "Symbols"
        case .commands: return "Commands"
        case .content: return "Content"
        case .git: return "Git"
        case .knowledge: return "Knowledge"
        case .run: return "Run"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "magnifyingglass"
        case .files: return "doc"
        case .symbols: return "curlybraces"
        case .commands: return "command"
        case .content: return "text.alignleft"
        case .git: return "arrow.triangle.branch"
        case .knowledge: return "book"
        case .run: return "play"
        }
    }
}
