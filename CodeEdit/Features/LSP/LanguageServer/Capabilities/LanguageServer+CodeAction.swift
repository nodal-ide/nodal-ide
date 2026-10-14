//
//  LanguageServer+CodeAction.swift
//  CodeEdit
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Returns the code actions available for the given range/context.
    func requestCodeActions(
        for documentURI: String,
        range: LSPRange,
        context: CodeActionContext
    ) async throws -> CodeActionResponse {
        do {
            let params = CodeActionParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                range: range,
                context: context
            )
            return try await lspInstance.codeAction(params)
        } catch {
            logger.warning("requestCodeActions: Error \(error)")
            throw error
        }
    }

    /// Resolves a code action that has a `data` field (its `edit` is computed lazily by the server).
    func requestCodeActionResolve(_ action: CodeAction) async throws -> CodeAction {
        do {
            return try await lspInstance.codeActionResolve(action)
        } catch {
            logger.warning("requestCodeActionResolve: Error \(error)")
            throw error
        }
    }
}
