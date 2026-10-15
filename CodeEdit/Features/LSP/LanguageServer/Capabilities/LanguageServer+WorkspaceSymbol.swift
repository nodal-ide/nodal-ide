//
//  LanguageServer+WorkspaceSymbol.swift
//  CodeEdit
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Searches the whole workspace for symbols matching a query.
    func requestWorkspaceSymbols(_ query: String) async throws -> WorkspaceSymbolResponse {
        do {
            return try await lspInstance.workspaceSymbol(WorkspaceSymbolParams(query: query))
        } catch {
            logger.warning("requestWorkspaceSymbols: Error \(error)")
            throw error
        }
    }
}
