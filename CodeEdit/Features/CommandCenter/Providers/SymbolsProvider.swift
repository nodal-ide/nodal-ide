//
//  SymbolsProvider.swift
//  CodeEdit
//
//  Command Center provider: project-wide symbols (native PHP index + LSP workspace/symbol).
//

import Foundation
import CodeEditLang
import LanguageServerProtocol

@MainActor
final class SymbolsProvider: CommandCenterProvider {
    let id = "symbols"
    let category: CommandCenterCategory = .symbols
    let priority = 90

    private weak var workspace: WorkspaceDocument?

    init(workspace: WorkspaceDocument) {
        self.workspace = workspace
    }

    func search(_ query: String) async -> [CommandCenterItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let workspace else { return [] }

        var items: [CommandCenterItem] = []

        // Native PHP workspace index.
        if let root = workspace.fileURL {
            let index = PHPWorkspaceIndex.shared.index(for: root)
            items += index.symbols(prefix: trimmed, limit: 100).map { symbol in
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

        // LSP workspace symbols for the active file's language.
        items += await lspSymbols(trimmed, workspace: workspace)
        return items
    }

    // MARK: - LSP

    private func lspSymbols(_ query: String, workspace: WorkspaceDocument) async -> [CommandCenterItem] {
        guard let document = workspace.editorManager?.activeEditor.selectedTab?.file.fileDocument,
              let language = document.getLanguage().lspLanguage,
              let lsp = ServiceContainer.resolve(.singleton, LSPService.self),
              let client = lsp.languageClient(for: language, workspacePath: workspace.fileURL?.absolutePath ?? ""),
              let response = try? await client.requestWorkspaceSymbols(query) else {
            return []
        }

        switch response {
        case .optionA(let infos):
            return infos.compactMap { info in
                guard let url = URL(string: info.location.uri) else { return nil }
                let start = info.location.range.start
                return CommandCenterItem(
                    id: "lspsym:\(info.location.uri):\(start.line):\(start.character):\(info.name)",
                    title: info.name,
                    subtitle: info.containerName ?? url.lastPathComponent,
                    systemImage: Self.icon(forLSPKind: info.kind),
                    category: .symbols,
                    kind: .position(url, start.line, start.character)
                )
            }
        case .optionB(let symbols):
            return symbols.compactMap { symbol in
                guard let location = symbol.location else { return nil }
                switch location {
                case .optionA(let loc):
                    guard let url = URL(string: loc.uri) else { return nil }
                    let start = loc.range.start
                    return CommandCenterItem(
                        id: "lspsym:\(loc.uri):\(start.line):\(start.character):\(symbol.name)",
                        title: symbol.name,
                        subtitle: symbol.containerName,
                        systemImage: Self.icon(forLSPKind: symbol.kind),
                        category: .symbols,
                        kind: .position(url, start.line, start.character)
                    )
                case .optionB(let documentID):
                    guard let url = URL(string: documentID.uri) else { return nil }
                    return CommandCenterItem(
                        id: "lspsym:\(documentID.uri):\(symbol.name)",
                        title: symbol.name,
                        subtitle: symbol.containerName,
                        systemImage: Self.icon(forLSPKind: symbol.kind),
                        category: .symbols,
                        kind: .file(url, nil)
                    )
                }
            }
        }
    }

    // MARK: - Icons

    private static func icon(for kind: CodeEditLang.SymbolKind?) -> String {
        switch kind {
        case .class, .enum, .interface, .namespace:
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

    private static func icon(forLSPKind kind: LanguageServerProtocol.SymbolKind) -> String {
        switch kind {
        case .class, .enum, .interface, .namespace, .module:
            return "cube"
        case .method, .function, .constructor:
            return "function"
        case .property, .field, .variable:
            return "square.on.square"
        case .constant:
            return "number"
        default:
            return "textformat"
        }
    }
}
