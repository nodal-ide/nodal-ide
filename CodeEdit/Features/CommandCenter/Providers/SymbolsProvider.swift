//
//  SymbolsProvider.swift
//  CodeEdit
//
//  Command Center provider: project-wide symbols (native PHP workspace index).
//

import Foundation
import CodeEditLang

@MainActor
final class SymbolsProvider: CommandCenterProvider {
    let id = "symbols"
    let category: CommandCenterCategory = .symbols
    let priority = 90

    private let workspaceURL: URL

    init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
    }

    func search(_ query: String) async -> [CommandCenterItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let index = PHPWorkspaceIndex.shared.index(for: workspaceURL)
        return index.symbols(prefix: trimmed, limit: 100).map { symbol in
            CommandCenterItem(
                id: "sym:\(symbol.fullyQualifiedName):\(symbol.fileURL.path):\(symbol.nameRange.location)",
                title: symbol.name,
                subtitle: symbol.container ?? symbol.namespace ?? symbol.fullyQualifiedName,
                systemImage: Self.icon(for: symbol.kind),
                category: .symbols,
                kind: .symbol(symbol.fileURL, symbol.nameRange)
            )
        }
    }

    private static func icon(for kind: SymbolKind?) -> String {
        switch kind {
        case .class, .enum, .interface:
            return "cube"
        case .function, .method:
            return "function"
        case .property, .variable:
            return "square.on.square"
        case .constant:
            return "number"
        default:
            return "textformat"
        }
    }
}
