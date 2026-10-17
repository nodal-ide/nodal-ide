//
//  LanguageServer+SemanticTokens.swift
//  CodeEdit
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Whether the server advertised support for semantic tokens. Servers like the CSS language server don't,
    /// so requesting them just produces `-32601 Unhandled method` errors.
    var supportsSemanticTokens: Bool {
        serverCapabilities.semanticTokensProvider != nil
    }

    func requestSemanticTokens(for documentURI: String) async throws -> SemanticTokensResponse {
        guard supportsSemanticTokens else {
            return SemanticTokens(data: [])
        }
        let params = SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: documentURI))
        do {
            return try await lspInstance.semanticTokensFull(params)
        } catch {
            logger.warning("requestSemanticTokens full: Error \(error)")
            throw error
        }
    }

    func requestSemanticTokens(
        for documentURI: String,
        previousResultId: String
    ) async throws -> SemanticTokensDeltaResponse {
        guard supportsSemanticTokens else {
            return nil
        }
        let params = SemanticTokensDeltaParams(
            textDocument: TextDocumentIdentifier(uri: documentURI),
            previousResultId: previousResultId
        )
        do {
            return try await lspInstance.semanticTokensFullDelta(params)
        } catch {
            logger.warning("requestSemanticTokens versioned: Error \(error)")
            throw error
        }
    }
}
